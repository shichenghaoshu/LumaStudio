import SwiftUI
import AppKit

enum StudioPalette {
    static let chrome=Color(white:0.085)
    static let panel=Color(white:0.105)
    static let canvas=Color(white:0.035)
    static let line=Color.white.opacity(0.075)
}

/// The supplied mark is displayed unchanged, including its porcelain background.
struct ShiguangBrand: View {
    var compact=false
    var body: some View {
        HStack(spacing:10) {
            Image("ShiguangMark").resizable().scaledToFit()
                .frame(width:compact ? 32 : 38,height:compact ? 32 : 38)
                .clipShape(RoundedRectangle(cornerRadius:compact ? 9 : 11))
                .accessibilityHidden(true)
            if !compact {
                VStack(alignment:.leading,spacing:2) {
                    Text("拾光").font(.system(size:19,weight:.semibold)).tracking(3)
                    Text("影像工作台").font(.system(size:9,weight:.medium)).foregroundStyle(.secondary).tracking(1)
                }
            }
        }.accessibilityElement(children:.ignore).accessibilityLabel("拾光")
    }
}

struct StudioButtonStyle: ButtonStyle {
    enum Role {case quiet,primary,icon,tool}
    var role: Role = .quiet
    var selected=false
    var feedback=true
    func makeBody(configuration: Configuration)->some View {
        InteractiveBody(configuration:configuration,role:role,selected:selected,feedback:feedback)
    }
    private struct InteractiveBody: View {
        let configuration: ButtonStyle.Configuration
        let role: Role
        let selected: Bool
        let feedback: Bool
        @Environment(\.isEnabled) private var enabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @AppStorage("shiguang.interfaceAnimations") private var animations=true
        @AppStorage("shiguang.hapticFeedback") private var haptics=true
        @State private var hovered=false
        private var motion: Animation? {reduceMotion || !animations ? nil : .easeOut(duration:0.12)}
        private var fill: Color {
            if role == .primary {return studioAccent.opacity(configuration.isPressed ? 0.78 : (hovered ? 1 : 0.94))}
            if configuration.isPressed {return Color.white.opacity(0.14)}
            if selected {return studioAccent.opacity(hovered ? 0.18 : 0.12)}
            return Color.white.opacity(hovered ? 0.075 : 0)
        }
        var body: some View {
            configuration.label
                .padding(.horizontal,role == .primary ? 14 : (role == .quiet ? 8 : 0))
                .padding(.vertical,role == .primary || role == .quiet ? 6 : 0)
                .frame(minWidth:role == .icon ? 32 : 0,minHeight:role == .tool ? 48 : 32)
                .foregroundStyle(role == .primary ? Color.black : (selected ? studioAccent : Color.white.opacity(hovered ? 0.96 : 0.77)))
                .background(fill,in:RoundedRectangle(cornerRadius:8))
                .overlay(RoundedRectangle(cornerRadius:8).strokeBorder(selected ? studioAccent.opacity(0.25) : Color.white.opacity(role == .primary ? 0.12 : 0),lineWidth:1))
                .contentShape(RoundedRectangle(cornerRadius:8))
                .scaleEffect(configuration.isPressed && !reduceMotion && animations ? 0.97 : 1)
                .opacity(enabled ? 1 : 0.34)
                .onHover{hovered=$0}
                .animation(motion,value:configuration.isPressed)
                .animation(motion,value:hovered)
                .animation(motion,value:selected)
                .onChange(of:configuration.isPressed){_,pressed in
                    if pressed && enabled && feedback && haptics {
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment,performanceTime:.now)
                    }
                }
        }
    }
}

struct StudioAppearanceSettings: View {
    @AppStorage("shiguang.hapticFeedback") private var haptics=true
    @AppStorage("shiguang.interfaceAnimations") private var animations=true
    var body: some View {
        VStack(alignment:.leading,spacing:24) {
            ShiguangBrand()
            VStack(alignment:.leading,spacing:16) {
                Toggle("按钮触感反馈",isOn:$haptics)
                Text("在支持触感反馈的触控板上提供轻触反馈。鼠标仍有按下与悬停反馈。")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("轻量界面动画",isOn:$animations)
                Text("系统开启“减少动态效果”时，自动关闭位移和缩放动画。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(28).frame(width:400).preferredColorScheme(.dark).tint(studioAccent)
    }
}
