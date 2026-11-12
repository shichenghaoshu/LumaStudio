# LumaStudio

原生、非破坏性的摄影工作台。当前交付为 **Mac 0.3.0 Edge AI 开发版**，支持本地离线修图，也可选择自己的在线模型 API。保留拍摄、修图、批量、大画布、四类调整面板和 Agent 处理过程。应用内原生集成 llama.cpp，核心功能不依赖 Python 或 Ollama 服务。iPad 旧工程保留，本次源码运行库只提供 Mac，iPad 构建与验收暂缓。

0.3.0 新增 **在线模型设置、MetalPetal GPU 美颜、Mac 麦克风听写、小智 MCP、本机 HTTP 与 MCP stdio 语音接口**。使用左侧「接入」配置，完整步骤与请求示例见 [接入说明](Documentation/INTEGRATIONS.md)。API 密钥和小智接入点存系统钥匙串，默认不上传照片；本地模式仍可独立使用。源码仓库：[shichenghaoshu/LumaStudio](https://github.com/shichenghaoshu/LumaStudio)（私有）。

新增 [Agent 处理过程页面](Documentation/AGENT_PROCESS.md)：实时执行步骤、阶段耗时、真实预览、逐轮指标与版本采用；入口位于修图页顶部“处理过程”及助手面板。界面改造和实际检查见 [Mac 工作区](Documentation/UI_WORKSPACE.md)；新增功能和未完成的训练工作见 [Edge AI 当前状态](Documentation/EDGE_AI.md)；训练工具见 [Training/README.md](Training/README.md)。当前 Qwen 1.5B 是通用基础模型，尚未进行 LumaStudio 专业任务训练。

**实际边界：** 第一代 G9 的真实 RW2 样片已解码并全分辨率导出；G9 实机拍摄尚未验收。美颜实际使用 MetalPetal 高通平滑 + Vision／传统皮肤蒙版，没有捆绑训练好的商业精修网络。本次在线 API 和小智 WebSocket 通过本机协议服务验证；没有使用真实付费模型密钥或小智账号，真人语音识别质量未验收。

## 开始使用

1. 在 `Deliverables` 中打开 `LumaStudio.app`（Mac 本机临时签名版），或用 Xcode 打开 `LumaStudio.xcodeproj`。
2. **修图**：导入照片/文件夹，右侧使用“调色／人像／配方／助手”面板。需要自然语言辅助时打开“助手”，输入“自然提亮，暖一点，不要美颜”等要求，点击“生成并预览”。可打开顶部“处理过程”查看实际执行、原图对照、逐轮参数与指标，采用选中的版本；仍可撤销／重做和修改参数，最后确认导出。画布上方提供缩放、原图与分屏对比；底部可查找照片、筛选 RAW 和进入批量。菜单“工作区”提供紧凑与标准布局。
3. **拍摄**：用官方 LUMIX Tether 连接 G9，选择 PC(Tether)，将保存目录设为 `~/Pictures/LumaStudio/Inbox`。本应用监听稳定的新文件并复制原件到图库、生成缩略图、可自动美颜。内嵌实时取景不可用，需在 Tether 中取景。
4. **批量**：先在修图页预览当前配方，再到批量页勾选照片，点击处理并导出到图库本地 Exports；菜单中可另选输出文件夹。暂停在当前照片处理完成后生效；取消会等待当前写入任务退出。
5. **模型**：点击左侧“模型”安装、切换或卸载本地模型包。当前这台 Mac 已安装本地 Qwen 1.5B 基础模型；没有可用模型或输出检查失败时使用本地规则。风格只在点击“记住这个风格”后保存在本机。
6. **接入**：配置通义、DeepSeek、OpenAI 或兼容 API，切换方案来源；在「语音与小智」保存自己的 MCP 接入点，或启动仅本机可访问的语音 HTTP 接口。默认外部要求进入待处理列表。助手／处理过程中的麦克风可听写修图文字。
7. **局域网（历史基础能力，本轮不做 iPad 验收）**：旧版代码保留，当前 Mac 主界面不以跨设备功能为交付范围。

导出主按钮直接保存到当前图库的 Exports；旁边菜单可改用指定文件夹。导入也支持将照片直接拖到画布。导出支持 JPEG、PNG 和 16 位 TIFF，始终创建新文件。所有编辑参数独立保存，原始照片不被修改。图库可通过“导入 → 选择图库位置”改到用户选择的本地目录；更换图库不会自动移动已有图库。

## 工程与构建

要求 Xcode 16.4 或兼容的新版本；最低运行系统 macOS 14 / iPadOS 17。此机器验证环境为 macOS 15.6.1、Apple M2 Pro、Swift 6.1.2；项目使用 Swift 5 语言模式与 Swift Concurrency。

```sh
git clone https://github.com/shichenghaoshu/LumaStudio.git
cd LumaStudio

# Mac：本机可运行的 Release 应用，临时签名
xcodebuild -project LumaStudio.xcodeproj -scheme LumaStudioMac \
  -configuration Release -derivedDataPath ReleaseData \
  CODE_SIGN_IDENTITY=- build

# 共享模块测试；未提供外部素材／权重时，相应项明确跳过
swift test
python3 -m unittest discover -s Tests/VoiceMCPTests -v

# 已取得授权的真实样片在本机时
LUMA_RAW_FIXTURE="$PWD/work/fixtures/G9-3219.RW2" \
LUMA_PORTRAIT_FIXTURE="$PWD/work/fixtures/portrait.jpg" swift test
```

首次构建需联网解析固定版本的 MetalPetal 与 swift-collections。Mac 原生运行库已随源码提供，GGUF 权重不在仓库内；缺少本地模型时可用规则或配置自己的在线模型。Xcode 的 `LumaStudioMac` scheme 已共享。详见 [构建与安装](Documentation/BUILD.md)。

## 代码结构

- `Apps/LumaStudioMac` / `Apps/LumaStudioPad`：各平台入口与页面；`Apps/Shared`：共用状态管理和工作台控件。
- `Package.swift`：本地 Swift Package，提供统一 `PhotoCore`，原生推理库随工程提供。
- `Packages/PhotoDomain`：Recipe / EditRecipe、JSON Schema、参数、照片与相机能力、统一日志。
- `Packages/AgentCore` / `ToolRegistry`：本地规划、原生 Qwen、生成约束、工具注册、指令安全检查、编辑闭环。
- `Packages/VisionEngine` / `ImageEngine` / `Evaluator`：图像分析、人物／背景区域、统一原生引擎和确定性评价。
- `Packages/ModelManager` / `LocalMemory`：本地模型校验、安装／回滚、设备信息、风格偏好与逐轮记录。
- `Training`：独立数据生成、SFT／蒸馏／DPO、专用模型、量化和转换工具；正式训练尚未执行。
- `Packages/CameraKit` / `PanasonicG9` / `TetherFolderWatcher`：设备接口、第一代 G9 原生实验与稳定目录监听。
- `Packages/BeautyEngine`：实际 MetalPetal GPU 高通平滑、Vision、关键点保护、可选 Core ML、guided mask、纹理恢复与传统回退。
- `Packages/CloudModel`：URLSession 在线规划、两种 API 格式、钥匙串凭据、严格配方与图片上传约束。
- `Packages/VoiceBridge`：小智 MCP WebSocket、loopback HTTP、最终文字与有界去重；`Tools/VoiceMCP`：可选 stdio 适配器。
- `Packages/ColorEngine`：六个真实 LUT、Lab、直方图、参考色彩档案与肤色保护。
- `Packages/PhotoPipeline`：ImageIO / CIRAWFilter、Metal Core Image context、三级处理、预览缓存、非覆盖导出。
- `Packages/BatchEngine`：有限并发、暂停/继续/取消、重试、任务 JSON 恢复。
- `Packages/LocalLibrary`：SwiftData ModelActor、本地索引、SHA256 去重、原片副本和 RAW/JPEG 配对。
- `Packages/LocalSync`：Bonjour、TLS-PSK、Keychain 配对、分块与完整性校验、受能力限制的远程快门。
- `Tests`：共享模块的单元及集成测试；`Tools/LumaDiagnostics`：真实样片与性能验证工具。
- `Resources`：自制图标、六种 LUT、示例配方；没有未授权模型或商业素材。

## 验证与未完成项

最终实际结果见 [验收记录](Documentation/VALIDATION.md)、[性能报告](Documentation/PERFORMANCE.md)、[逐项状态](Documentation/STATUS.md)。原始日志和输出位于 `Artifacts`，不包含用户私有照片测试数据。

G9 实机、M1 真机、M 系列实体 iPad、跨实体设备传输、100 张不同场景的连续运行、专业人像主观质量评审仍需完成。该版本没有 G9 内嵌实时取景、拍摄参数调节、G9 直接 Wi-Fi 控制、液化、五官重塑或自动内容填补；这些入口明确禁用或未开放。
