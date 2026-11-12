# 构建、安装与日常操作

> 当前版本 Mac 0.3.0。新增在线／语音接入见 [INTEGRATIONS.md](INTEGRATIONS.md)，训练边界见 [EDGE_AI.md](EDGE_AI.md)。以下 iPad 段落保留为 0.1 历史记录：本次仓库只打包 Mac llama 运行库，不支持直接据此构建 iPad。

## 本次开发环境

Apple M2 Pro (arm64)、macOS 15.6.1、Xcode 16.4 (16F6)、Swift 6.1.2。macOS SDK 15.5，iOS/iPadOS SDK 18.5，已安装 iOS 18.6 模拟器 runtime。最低部署目标 macOS 14 / iPadOS 17，Mac target 仅 arm64，iPad target device family 为 2。

工程已经生成，正常打开和构建不需要额外包管理工具。首次解析 Swift Package 需联网获取固定版本 MetalPetal 1.25.2 与 swift-collections 1.1.4；`Package.resolved` 已提交。`Vendor/llama-runtime.xcframework` 是 b12110 未修改的 macOS 通用切片，来源和哈希见同目录 `runtime-provenance.json`。GGUF 权重不在仓库中。`Scripts/generate_project.py` 可重建工程与共享 schemes；图标生成工具均不进入应用运行环境。

## Mac

在项目根目录执行：

```sh
xcodebuild -project LumaStudio.xcodeproj -scheme LumaStudioMac \
  -configuration Release -derivedDataPath ReleaseData \
  CODE_SIGN_IDENTITY=- build
open ReleaseData/Build/Products/Release/LumaStudioMac.app
```

本机 `Deliverables/LumaStudio.app` 是该构建的复制品，可直接打开；压缩包未提交 GitHub。Mac 未启用 App Sandbox，以便默认 Inbox 与用户指定摄影目录正常访问。本机临时签名版关闭 Hardened Runtime，使没有 Team ID 的内嵌 llama 运行库能够加载；正式分发需要同团队签名、启用 Hardened Runtime 与公证。本包未做 Developer ID 公证。

## iPad 模拟器（0.1 历史命令，当前包未支持）

```sh
xcodebuild -project LumaStudio.xcodeproj -scheme LumaStudioPad \
  -configuration Release -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedDataPad CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES build
xcrun simctl boot 'iPad Pro 11-inch (M4)'
xcrun simctl install booted DerivedDataPad/Build/Products/Release-iphonesimulator/LumaStudioPad.app
xcrun simctl launch booted studio.luma.pad
```

若模拟器已启动，跳过 boot 一行。模拟器运行不是实体 M4 iPad 的性能或硬件验证。

## iPad 真机（0.1 历史命令，当前包未支持）

无签名的编译检查：

```sh
xcodebuild -project LumaStudio.xcodeproj -scheme LumaStudioPad \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath DerivedDataDevice CODE_SIGNING_ALLOWED=NO build
```

真正安装时，打开工程选择 LumaStudioPad，在 Signing & Capabilities 选择自己的 Team，插入并信任 iPad，开启其 Developer Mode，然后选择该设备运行。`Deliverables/LumaStudioPad-device-unsigned.app` 只证明设备代码已编译，不能直接当作可安装包。没有使用或索取开发者账户密码。

iPad 的本地网络访问说明和 `_lumastudio._tcp` Bonjour service 已写入 Info.plist；仅在使用局域网功能时触发授权。二维码由系统相机扫描并通过 `lumastudio` URL scheme 打开应用，也可复制链接粘贴。

## 测试与样片

```sh
swift test
python3 -m unittest discover -s Tests/VoiceMCPTests -v
# 含真实 G9 与人像的全部验收
LUMA_RAW_FIXTURE="$PWD/work/fixtures/G9-3219.RW2" \
LUMA_PORTRAIT_FIXTURE="$PWD/work/fixtures/portrait.jpg" swift test
swift run -c release LumaDiagnostics inspect work/fixtures/G9-3219.RW2 Artifacts/MyRAWCheck
```

不设置 fixture 时，涉及外部样片的测试会明确 skipped；不能把这种运行当作 RAW 或人像已验证。重新下载样片可用 `Scripts/fetch_fixtures.sh`，来源和 SHA256 均已固定。

批量压力测试由 `Scripts/measure_batch.py` 启动 Release diagnostics 并每秒采样 RSS，应用本身不依赖 Python。报告说明同一真实样片重复 100 次，不能用来代替不同场景大图库测试。
