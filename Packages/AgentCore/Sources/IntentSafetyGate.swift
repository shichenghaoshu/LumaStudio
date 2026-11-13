import Foundation
import PhotoDomain

/// A generic base model may change unrelated controls while producing perfectly valid JSON.
/// Preserve the existing/draft controls for explicit, narrow requests; the evaluator then
/// measures whether the requested direction actually appeared in the rendered photograph.
public enum IntentSafetyGate {
    public static func enforce(_ proposed: EditRecipe,context: PlanningContext) throws -> EditRecipe {
        var r=proposed
        let intent=InstructionParser.parse(context.instruction),t=context.instruction.lowercased()
        let draft=try LocalRulePlanner().plan(context)
        let style=["风格","胶片","电影","日系","日式","通透","滤镜","film","cinematic","style","look"].contains(where:t.contains)
        let narrow=intent.brightnessDirection != 0 || intent.saturationDirection != 0 || intent.warmthDirection != 0 || intent.beautyRequested || intent.beautyForbidden || intent.requestedLocalRegion != nil
        if narrow && !style {
            if intent.brightnessDirection==0 && !["曝光","亮度","exposure","brightness"].contains(where:t.contains) { r.global.exposure=draft.global.exposure }
            if intent.saturationDirection==0 { r.global.saturation=draft.global.saturation }
            if intent.warmthDirection==0 && !["白平衡","色温","white balance","temperature"].contains(where:t.contains) { r.global.temperature=draft.global.temperature }
            if !["对比","contrast"].contains(where:t.contains) { r.global.contrast=draft.global.contrast }
            if !["亮度","brightness"].contains(where:t.contains) {r.global.brightness=draft.global.brightness}
            if !["高光","highlight"].contains(where:t.contains) { r.global.highlights=draft.global.highlights }
            if !["阴影","暗部","shadow"].contains(where:t.contains) { r.global.shadows=draft.global.shadows }
            if !["白色色阶","white point"].contains(where:t.contains) { r.global.whites=draft.global.whites }
            if !["黑色色阶","black point"].contains(where:t.contains) { r.global.blacks=draft.global.blacks }
            if !["色调","tint"].contains(where:t.contains) { r.global.tint=draft.global.tint }
            if !["自然饱和","vibrance"].contains(where:t.contains) { r.global.vibrance=draft.global.vibrance }
            if !t.contains("清晰度") {r.global.clarity=draft.global.clarity}
            if !t.contains("纹理") {r.global.texture=draft.global.texture}
            if !t.contains("去朦胧") {r.global.dehaze=draft.global.dehaze}
            if !["参考","reference","hsl","曲线","色轮","分级","色阶","可选颜色","校准","色彩范围","色彩编辑器","红色","橙色","黄色","绿色","青色","蓝色","紫色","洋红"].contains(where:t.contains) { r.color=draft.color }
            if !intent.beautyRequested { r.beauty=draft.beauty }
            if intent.requestedLocalRegion != nil { r.global=draft.global }
        }
        if let current=context.currentRecipe {
            if intent.requestedLocalRegion==nil,!t.contains("删除蒙版"),!t.contains("重置") {r.masks=current.masks}
            else if let region=intent.requestedLocalRegion {r.masks=current.masks.filter{$0.kind != region}+r.masks.filter{$0.kind==region}}
        }
        LocalRulePlanner.applyBeautyRequest(context.instruction,to:&r,faceCount:context.analysis.faceCount)
        if !t.contains("瘦脸") {r.beauty.faceSlimming=draft.beauty.faceSlimming}
        if !t.contains("大眼") {r.beauty.eyeEnlargement=draft.beauty.eyeEnlargement}
        LocalRulePlanner.applyExplicitParameters(context.instruction,to:&r)
        r=ParameterLockPolicy.applying(r,preserving:context.currentRecipe)
        if intent.beautyForbidden || context.analysis.faceCount==0 { r.beauty.enabled=false }
        if r.color.referenceProfileID != context.referenceProfileID { r.color.referenceProfileID=nil }
        r.operations=[];try r.validateParameters();return r
    }
}
