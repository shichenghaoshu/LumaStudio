import CoreImage

/// CIRAWFilter runs this in scene-linear space before its output tone curve.
/// Apple's boostShadowAmount saturates at 1 on some decoders, despite the SDK's
/// documented 0...2 range; use an explicit linear-stage adjustment for both signs.
final class RAWLinearShadowFilter: CIFilter {
    @objc dynamic var inputImage: CIImage?
    let amount: Float
    init(amount: Float) {self.amount=amount;super.init()}
    required init?(coder: NSCoder) {amount=0;super.init(coder:coder)}
    private static let kernel=CIColorKernel(source:"""
    kernel vec4 rawShadows(__sample pixel, float amount) {
        float luminance=max(0.0,dot(pixel.rgb,vec3(0.2126,0.7152,0.0722)));
        float weight=exp(-luminance*6.0);
        return vec4(pixel.rgb*exp2(amount*2.0*weight),pixel.a);
    }
    """)!
    override var outputImage: CIImage? {
        guard let image=inputImage else {return nil}
        return Self.kernel.apply(extent:image.extent,arguments:[image,amount])
    }
}
