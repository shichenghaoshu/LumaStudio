import SwiftUI
import PhotoCore

struct ProPhotoMaskOverlay: View {
    @Bindable var model: AppModel
    let size: CGSize
    let paintingAllowed: Bool
    @State private var points=[BrushPoint]()
    var body: some View {
        ZStack {
            if model.showMaskOverlay,let mask=model.maskPreview {
                Color.red.opacity(0.4).mask{Image(decorative:mask,scale:1).resizable().frame(width:size.width,height:size.height).luminanceToAlpha()}.allowsHitTesting(false)
            }
            if model.drawingBrush,model.canDrawBrush,paintingAllowed {
                Canvas {ctx,_ in
                    guard !points.isEmpty else {return}
                    var path=Path();path.addLines(points.map{CGPoint(x:CGFloat($0.x)*size.width,y:CGFloat($0.y)*size.height)})
                    ctx.stroke(path,with:.color(.red.opacity(0.6)),style:StrokeStyle(lineWidth:CGFloat(model.activeMask?.brushSize ?? 0.06)*min(size.width,size.height),lineCap:.round,lineJoin:.round))
                }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0).onChanged{v in
                    let p=BrushPoint(x:Float(min(1,max(0,v.location.x/size.width))),y:Float(min(1,max(0,v.location.y/size.height))))
                    if points.count<2048 {points.append(p)}
                }.onEnded{_ in model.addBrushStroke(points);points=[]}).accessibilityLabel("局部画笔画布")
            }
        }.frame(width:size.width,height:size.height)
    }
}
