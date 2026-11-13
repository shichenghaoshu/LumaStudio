import SwiftUI
import PhotoCore

struct ProInspectorGroup<Content: View>: View {
    @Bindable var model: AppModel
    let title: String,ids: [String]
    @Binding var expanded: Bool
    let reset: ()->Void
    @ViewBuilder let content: ()->Content
    private var hidden: Bool {model.previewBypassedParameters==ids}
    private var locked: Bool {!ids.isEmpty && ids.allSatisfy{ParameterLockPolicy.isLocked($0,in:model.recipe.document)}}
    private var changed: Int {ids.filter{id in guard let p=ParameterCatalog.find(id) else{return false};return !p.isAutomatic(model.recipe.document) && abs(p.read(model.recipe.document)-p.defaultValue)>0.00001}.count}
    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            HStack(spacing:8) {
                Button{expanded.toggle()}label:{HStack(spacing:9){Image(systemName:expanded ? "chevron.down" : "chevron.right").font(.system(size:9,weight:.semibold)).frame(width:10);Text(title).font(.system(size:12,weight:.medium));if changed>0{Circle().fill(studioAccent).frame(width:4,height:4)};Spacer(minLength:2)}}.buttonStyle(.plain).accessibilityLabel((expanded ? "收起" : "展开")+title)
                Button{model.previewBypassedParameters=hidden ? [] : ids}label:{Image(systemName:hidden ? "eye.slash" : "eye").foregroundStyle(hidden ? studioAccent : Color.white.opacity(0.4))}.help("仅隐藏本组预览，配方与导出保持当前参数").accessibilityLabel((hidden ? "显示" : "暂时隐藏")+title+"效果")
                Button{model.toggleParameterLocks(ids)}label:{Image(systemName:locked ? "lock.fill" : "lock.open").foregroundStyle(locked ? studioAccent : Color.white.opacity(0.4))}.help("锁定本组，AI 保留这些值").accessibilityLabel((locked ? "解锁" : "锁定")+title+"组")
                Button(action:reset){Image(systemName:"arrow.counterclockwise").foregroundStyle(.white.opacity(0.4))}.help("重置本组").accessibilityLabel("重置"+title+"组")
            }.buttonStyle(.plain).font(.system(size:10)).padding(.horizontal,12).frame(height:43)
            if expanded {VStack(alignment:.leading,spacing:13){content()}.padding(.horizontal,12).padding(.bottom,16)}
        }.background(Color(white:0.145),in:RoundedRectangle(cornerRadius:9))
    }
}

struct ProHistogramPanel: View {
    @Bindable var model: AppModel
    @State private var data=ImageHistogram()
    var body: some View {
        VStack(spacing:10) {
            HStack{Text("直方图").font(.system(size:10));Spacer();Text("RGB · sRGB 预览").font(.system(size:9)).foregroundStyle(.tertiary)}
            Canvas {ctx,size in
                let arrays=[data.red,data.green,data.blue],colors:[Color]=[.red,.green,.blue]
                let ceiling=max(1,arrays.flatMap{$0}.max() ?? 1)
                for (index,bins) in arrays.enumerated() {
                    var path=Path();path.move(to:CGPoint(x:0,y:size.height))
                    for (i,count) in bins.enumerated(){let point=CGPoint(x:Double(i)/95*size.width,y:size.height*(1-pow(count/ceiling,0.5)));path.addLine(to:point)}
                    path.addLine(to:CGPoint(x:size.width,y:size.height));path.closeSubpath()
                    ctx.fill(path,with:.color(colors[index].opacity(0.22)));ctx.stroke(path,with:.color(colors[index].opacity(0.7)),lineWidth:0.8)
                }
            }.frame(height:90).background(LinearGradient(colors:[.black,Color(white:0.07)],startPoint:.top,endPoint:.bottom)).clipShape(RoundedRectangle(cornerRadius:5)).accessibilityLabel("当前照片 RGB 直方图")
            HStack{Text(String(format:"暗部溢出 %.1f%%",data.shadows*100));Spacer();Text(String(format:"高光溢出 %.1f%%",data.highlights*100))}.font(.system(size:9)).monospacedDigit().foregroundStyle(.secondary)
            HStack(spacing:6) {
                Button{model.instruction="自动校正当前照片曝光与白平衡，恢复高光和阴影，不要美颜，不改变其他参数。";model.runAgent()}label:{Label("AI 校准",systemImage:"wand.and.stars").frame(maxWidth:.infinity)}
                Button{model.batchInstruction="逐张自动校正曝光和白平衡，恢复高光和阴影，不要美颜，保留其他参数。";model.batchAIEnabled=true;if model.selection.isEmpty{model.selection=Set(model.visibleAssets.map(\.id))};model.page = .batch}label:{Label("逐张校准…",systemImage:"photo.on.rectangle").frame(maxWidth:.infinity)}
            }.font(.system(size:10)).buttonStyle(.bordered).controlSize(.small).disabled(model.selected==nil || model.agentBusy)
        }.padding(12).background(Color(white:0.145),in:RoundedRectangle(cornerRadius:9))
            .task(id:model.preview.map{ObjectIdentifier($0)}) {
                guard let image=model.preview else {data=ImageHistogram();return}
                let measured=await Task.detached(priority:.utility){ImageHistogram.measure(image)}.value
                guard !Task.isCancelled else{return};data=measured
            }
    }
}
