import Foundation
import CoreImage
import CoreML
import CryptoKit
import PhotoDomain

/// Local inference only. The pretrained networks predict a blemish correction
/// and a blend layer, rather than replacing the face with a generated image.
final class LearnedRetouch {
    private struct Layers { let correction: CIImage; let blend: CIImage }
    private final class Cached: NSObject { let layers: Layers; init(_ layers: Layers) {self.layers=layers} }
    private final class Models {
        let detect: MLModel, heal: MLModel, blend: MLModel
        private let lock=NSLock()
        init() throws {
            let configuration=MLModelConfiguration();configuration.computeUnits = .all
            func load(_ name: String) throws -> MLModel {
                guard let url=Bundle.module.url(forResource:name,withExtension:"mlpackage",subdirectory:"RetouchModels") else {
                    throw LumaError.unsupported("本地 AI 精修模型缺失，请安装包含模型的 Mac 完整版；其他美颜仍可用。")
                }
                // Core ML clones weight files while compiling. On a protected
                // Desktop installation that filesystem operation can stall even
                // though ordinary reads succeed. Stage our own bundled bytes in
                // the app's temporary directory before invoking the compiler.
                let staging=FileManager.default.temporaryDirectory.appendingPathComponent("LumaRetouch-"+UUID().uuidString,isDirectory:true)
                defer {try? FileManager.default.removeItem(at:staging)}
                let local=try LearnedRetouch.stageModelPackage(at:url,in:staging)
                return try MLModel(contentsOf:MLModel.compileModel(at:local),configuration:configuration)
            }
            detect=try load("LumaBlemishDetect");heal=try load("LumaBlemishHeal");blend=try load("LumaRetouchBlend")
        }
        func synchronized<T>(_ body: () throws -> T) rethrows -> T {
            lock.lock();defer{lock.unlock()};return try body()
        }
    }
    // Share compiled networks, never photo results, across preview/export actors.
    private static let models: Result<Models,Error> = Result {try Models()}
    private let cache=NSCache<NSString,Cached>()
    private let kernel: CIColorKernel
    private(set) var inferenceCount=0
    private(set) var lastMilliseconds=0.0
    private(set) var lastFaceCount=0

    init() throws {
        cache.countLimit=8;cache.totalCostLimit=96*1024*1024
        guard let kernel=CIColorKernel(source:"""
        kernel vec4 lumaLearnedRetouch(__sample source, __sample correction, __sample blend, __sample skin, vec4 crop, vec4 face, float healing, float dodgeBurn) {
            vec2 p=destCoord();
            vec2 uv=(p-crop.xy)/crop.zw;
            float border=smoothstep(0.0,0.08,min(min(uv.x,1.0-uv.x),min(uv.y,1.0-uv.y)));
            vec2 f=(p-face.xy)/face.zw;
            float oval=1.0-smoothstep(0.82,1.0,dot(f,f));
            float mask=clamp(skin.r*border*oval,0.0,1.0);
            vec3 base=clamp(source.rgb,0.0,1.0);
            vec3 headroom=source.rgb-base;
            // The original training and blend equation operate in encoded sRGB.
            // CI evaluates this kernel in linear sRGB; transform explicitly.
            vec3 encoded=mix(12.92*base,1.055*pow(base,vec3(1.0/2.4))-0.055,step(vec3(0.0031308),base));
            vec3 repaired=clamp(encoded+correction.rgb*healing,0.0,1.0);
            vec3 mg=vec3(0.5)+(clamp(blend.rgb,0.0,1.0)-vec3(0.5))*dodgeBurn;
            vec3 retouched=(1.0-2.0*mg)*repaired*repaired+2.0*mg*repaired;
            vec3 linear=mix(retouched/12.92,pow((retouched+0.055)/1.055,vec3(2.4)),step(vec3(0.04045),retouched));
            return vec4(mix(source.rgb,linear+headroom,mask),source.a);
        }
        """) else {throw LumaError.unsupported("AI 精修混合内核编译失败")}
        self.kernel=kernel
    }

    static func stageModelPackage(at source: URL,in root: URL) throws -> URL {
        let fm=FileManager.default
        let destination=root.appendingPathComponent(source.lastPathComponent,isDirectory:true)
        try fm.createDirectory(at:destination,withIntermediateDirectories:true)
        // Relative names also avoid /var versus /private/var aliases in the
        // system temporary directory changing a URL's path-component count.
        guard let files=fm.enumerator(atPath:source.path) else {
            throw LumaError.corruptData("无法读取本地 AI 精修模型")
        }
        for case let relative as String in files {
            let file=source.appendingPathComponent(relative)
            let metadata=try file.resourceValues(forKeys:[.isDirectoryKey,.isRegularFileKey,.isSymbolicLinkKey])
            guard metadata.isSymbolicLink != true else {throw LumaError.corruptData("AI 精修模型包含无效链接")}
            let target=destination.appendingPathComponent(relative)
            if metadata.isDirectory == true {try fm.createDirectory(at:target,withIntermediateDirectories:true)}
            else if metadata.isRegularFile == true {
                // Deliberately use read/write, never copyItem/clonefile here.
                try Data(contentsOf:file).write(to:target,options:.atomic)
            } else {throw LumaError.corruptData("AI 精修模型包含无效文件")}
        }
        return destination
    }

    func apply(_ image: CIImage, settings: BeautySettings, analysis: SkinAnalysis, context: CIContext) throws -> CIImage {
        lastFaceCount=0
        guard settings.retouchBlemishes>0 || settings.retouchDodgeBurn>0 else {return image}
        let models=try Self.models.get()
        var result=image
        let start=Date()
        for face in analysis.faces {
            try Task.checkCancellation()
            let b=face.bounds,e=image.extent
            // Small faces have insufficient pixels for reliable local repair.
            guard min(b.width*e.width,b.height*e.height)>=100 else {continue}
            let side=max(b.width*e.width,b.height*e.height)*1.5
            let crop=CGRect(x:e.minX+b.midX*e.width-side/2,y:e.minY+b.midY*e.height-side/2,width:side,height:side).integral.intersection(e)
            guard !crop.isEmpty else {continue}
            let sample=try input(image,crop:crop,size:512,context:context)
            guard let bytes=sample.dataProvider?.data else {throw LumaError.invalidImage("AI 精修缓存输入")}
            let digest=SHA256.hash(data:bytes as Data).map{String(format:"%02x",$0)}.joined()
            let key="\(digest)|\(crop.width)x\(crop.height)" as NSString
            let layers: Layers
            if let cached=cache.object(forKey:key) {layers=cached.layers}
            else {
                layers=try models.synchronized {try predict(image,crop:crop,sample:sample,models:models,context:context)}
                cache.setObject(Cached(layers),forKey:key,cost:(576*576+512*512)*16)
                inferenceCount += 1
            }
            func positioned(_ input: CIImage) -> CIImage {
                input.transformed(by:CGAffineTransform(scaleX:crop.width/input.extent.width,y:crop.height/input.extent.height))
                    .transformed(by:CGAffineTransform(translationX:crop.minX,y:crop.minY))
            }
            let oval=CIVector(x:e.minX+b.midX*e.width,y:e.minY+(b.midY+0.03*b.height)*e.height,z:b.width*e.width*0.52,w:b.height*e.height*0.65)
            guard let edited=kernel.apply(extent:crop,arguments:[result,positioned(layers.correction),positioned(layers.blend),analysis.mask,CIVector(cgRect:crop),oval,settings.retouchBlemishes,settings.retouchDodgeBurn]) else {throw LumaError.invalidImage("AI 精修图层合成")}
            // A kernel's region of definition is not an alpha clip. Explicitly
            // crop before source-over, otherwise a later face can extend a
            // boundary pixel into protected hair/background outside its ROI.
            let regionMask=CIImage(color:.white).cropped(to:crop).composited(over:CIImage(color:.black).cropped(to:e))
            result=edited.cropped(to:crop).applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:result,kCIInputMaskImageKey:regionMask]).cropped(to:e)
            lastFaceCount += 1
        }
        lastMilliseconds=Date().timeIntervalSince(start)*1000
        return result
    }

    func clearCache() {cache.removeAllObjects()}

    private func input(_ image: CIImage,crop: CGRect,size: Int,context: CIContext) throws -> CGImage {
        let local=image.cropped(to:crop).transformed(by:CGAffineTransform(translationX:-crop.minX,y:-crop.minY))
            .transformed(by:CGAffineTransform(scaleX:CGFloat(size)/crop.width,y:CGFloat(size)/crop.height))
        guard let cg=context.createCGImage(local,from:CGRect(x:0,y:0,width:size,height:size),format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB)!) else {throw LumaError.invalidImage("AI 精修输入")}
        return cg
    }

    private func feature(_ image: CGImage,model: MLModel) throws -> MLFeatureValue {
        guard let constraint=model.modelDescription.inputDescriptionsByName["image"]?.imageConstraint else {throw LumaError.corruptData("AI 精修模型输入")}
        return try MLFeatureValue(cgImage:image,constraint:constraint,options:[:])
    }

    private func predict(_ image: CIImage,crop: CGRect,sample: CGImage,models: Models,context: CIContext) throws -> Layers {
        let detected=try models.detect.prediction(from:MLDictionaryFeatureProvider(dictionary:["image":try feature(input(image,crop:crop,size:768,context:context),model:models.detect)]))
        guard let probability=detected.featureValue(for:"probability")?.multiArrayValue else {throw LumaError.corruptData("AI 瑕疵概率缺失")}
        let values=try tensor(probability,channels:1,size:768)
        let keepType=models.heal.modelDescription.inputDescriptionsByName["keep"]?.multiArrayConstraint?.dataType ?? .float32
        let keep=try MLMultiArray(shape:[1,1,576,576],dataType:keepType)
        for y in 0..<576 {for x in 0..<576 {
            let p=values[min(767,y*768/576)*768+min(767,x*768/576)]
            let value: Float=p>=0.5 ? 0 : p>=0.35 ? 1-p : 1
            if keepType == .float16 {
                #if arch(arm64)
                keep.dataPointer.assumingMemoryBound(to:Float16.self)[y*576+x]=Float16(value)
                #else
                keep[y*576+x]=NSNumber(value:value)
                #endif
            }
            else {keep.dataPointer.assumingMemoryBound(to:Float.self)[y*576+x]=value}
        }}
        try Task.checkCancellation()
        let repair=try models.heal.prediction(from:MLDictionaryFeatureProvider(dictionary:["image":try feature(input(image,crop:crop,size:576,context:context),model:models.heal),"keep":MLFeatureValue(multiArray:keep)]))
        guard let correction=repair.featureValue(for:"correction")?.multiArrayValue else {throw LumaError.corruptData("AI 修复图层缺失")}
        let correctionImage=try imageTensor(correction,size:576)
        // Predict the blend from the repaired image, using the same normalization
        // as the reference pipeline. This intermediate is never the final output.
        let resized=correctionImage.transformed(by:CGAffineTransform(scaleX:512.0/576,y:512.0/576))
        let repaired=try Self.repairForBlend(sample:sample,correction:resized,context:context)
        try Task.checkCancellation()
        let blended=try models.blend.prediction(from:MLDictionaryFeatureProvider(dictionary:["image":try feature(repaired,model:models.blend)]))
        guard let blend=blended.featureValue(for:"blend")?.multiArrayValue else {throw LumaError.corruptData("AI 光影图层缺失")}
        return Layers(correction:correctionImage,blend:try imageTensor(blend,size:512))
    }

    private static func repairForBlend(sample: CGImage,correction: CIImage,context: CIContext) throws -> CGImage {
        // Work in an explicitly gamma-encoded context to add the learned delta.
        // No automatic CI color transform may be applied to a correction tensor.
        let rect=CGRect(x:0,y:0,width:512,height:512)
        var bytes=[UInt8](repeating:0,count:512*512*4)
        context.render(CIImage(cgImage:sample),toBitmap:&bytes,rowBytes:512*4,bounds:rect,format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB)!)
        var delta=[Float](repeating:0,count:512*512*4)
        context.render(correction,toBitmap:&delta,rowBytes:512*16,bounds:rect,format:.RGBAf,colorSpace:nil)
        for i in 0..<(512*512) {for c in 0..<3 {bytes[i*4+c]=UInt8(min(255,max(0,(Float(bytes[i*4+c])+delta[i*4+c]*255).rounded())))}}
        guard let provider=CGDataProvider(data:Data(bytes) as CFData),let result=CGImage(width:512,height:512,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:512*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent) else {throw LumaError.invalidImage("AI 精修光影输入")}
        return result
    }

    private func tensor(_ array: MLMultiArray,channels: Int,size: Int) throws -> [Float] {
        guard [.float32,.float16].contains(array.dataType),array.shape.map(\.intValue)==[1,channels,size,size] else {throw LumaError.corruptData("AI 精修张量格式：\(array.shape)，\(array.dataType)")}
        let s=array.strides.map(\.intValue)
        var values=[Float](repeating:0,count:channels*size*size)
        for c in 0..<channels {for y in 0..<size {for x in 0..<size {
            let offset=c*s[1]+y*s[2]+x*s[3]
            let value: Float
            if array.dataType == .float16 {
                #if arch(arm64)
                value=Float(array.dataPointer.assumingMemoryBound(to:Float16.self)[offset])
                #else
                value=array[[0,NSNumber(value:c),NSNumber(value:y),NSNumber(value:x)]].floatValue
                #endif
            } else {value=array.dataPointer.assumingMemoryBound(to:Float.self)[offset]}
            guard value.isFinite else {throw LumaError.corruptData("AI 精修产生无效像素")}
            values[(c*size+y)*size+x]=value
        }}}
        return values
    }

    private func imageTensor(_ array: MLMultiArray,size: Int) throws -> CIImage {
        let values=try tensor(array,channels:3,size:size)
        var rgba=[Float](repeating:1,count:size*size*4)
        for i in 0..<(size*size) {for c in 0..<3 {rgba[i*4+c]=values[c*size*size+i]}}
        return CIImage(bitmapData:rgba.withUnsafeBytes{Data($0)},bytesPerRow:size*16,size:CGSize(width:size,height:size),format:.RGBAf,colorSpace:nil)
    }
}
