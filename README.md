# LumaStudio

**0.6.0 Preview 创作者插件**新增 Mac 创作中心：贡献 LUT、调色配方、局部工具和 AI 方法，搜索、试用、收藏、评分与版本安装。四类工具共用编辑器 / 批量 / Agent 执行接口。社区为随包运行的本机服务；商业许可可登记价格和条款，公网社区、支付、分账尚未接通。见[创作者插件说明](Documentation/CREATOR_PLUGINS.md)。

**稳定版 0.5.5 (24)** 已发布：41 款内置风格中含 11 款相机灵感仿色，覆盖徕卡、哈苏与富士方向；152 项本地 Release 检查和对应 CI、原生操作验收通过。仿色是开源或原创近似，不是厂商官方校准。见[仿色来源与实际验证](Documentation/CAMERA_COLOR_LOOKS.md)。

**0.5.4 (23) 中式美颜**组合本地 AI 祛瑕／光影均肤、磨皮、美白红润、瘦脸和大眼，提供轻柔／标准／更强三档；常驻按钮及 ⇧⌘B 直达中式标准预设，偏自然的 AI 精修保留独立入口。新增眉眼轮廓保护与公开侧脸、低照样图检查；144 项本地 Release 检查、对应源码 CI 与 17 组原生界面检查通过，实际 GUI 原尺寸批量导出 10/10、0 失败。详情见[中式美颜与验证边界](Documentation/CHINESE_BEAUTY_0.5.4.md)。

历史 0.5.4 (22) 自然 AI 精修已通过 138 项本地 Release 检查与对应安装包的原生验收，保存在独立历史候选目录；该验收不覆盖本次中式 (23) 的新界面与效果。三个本地 Core ML 模块及其开放许可继续随包提供，详见[自然精修阶段记录](Documentation/RETOUCH_0.5.4.md)。

0.5.3 (19) Mac 完成[快捷修图操作](Documentation/WORKFLOW_EFFICIENCY.md)：常驻强效美颜、上一张／下一张、原图与导出快捷键，以及粘贴／拖入文件夹路径。独立图库已实际验证美颜、参数锁、同步与撤回、重启保存和原尺寸导出；修复了目标照片打开时撤回同步又被旧预览覆盖的问题。

原生、非破坏性的摄影工作台。Mac 稳定版为 **0.5.5 (24)**，创作者插件分支为 **0.6.0 Preview (25)**，面向 macOS 14 及以上 Apple 芯片；0.5.3 (19) 历史包保留。可以离线修图，也可选择自己的在线模型 API。应用原生集成 llama.cpp，核心功能不依赖 Python 或 Ollama。Android / Windows 客户端保留 0.5.0，说明与构建见 [跨平台客户端](Apps/LumaStudioCross/README.md)。iPad 旧工程保留，本次不做 iPad 构建与验收。

[下载 Mac 稳定版 0.5.5](https://github.com/shichenghaoshu/LumaStudio/releases/tag/v0.5.5) · [Windows / Android 0.5.0](https://github.com/shichenghaoshu/LumaStudio/releases/tag/v0.5.0) · [0.5.4 中式美颜说明](Documentation/CHINESE_BEAUTY_0.5.4.md) · [0.5.3 历史版](https://github.com/shichenghaoshu/LumaStudio/releases/tag/v0.5.3)

**0.5.2 历史算法验收**保留120项Release检查、184参数逐项证据和真实DeepSeek执行。详见[实际算法验收范围](Documentation/ALGORITHM_ACCEPTANCE.md)；旧记录的时间与版本边界保留，不视为本轮新的在线调用。

**0.5.3 美颜优化**提供保边强效磨皮、连续皮肤蒙版、按人脸区域处理，以及轻柔／标准／更强三档预设力度、一键强效和美颜专用同步入口。预设保留已锁定的参数，仍保存为普通 EditRecipe v2 配方。132项本机Release检查、12张独立照片及最终原生操作的证据范围见[美颜优化](Documentation/BEAUTY_OPTIMIZATION.md)。

[Mac 0.5.1 性能更新](Documentation/RELEASE_0.5.1.md)提供交互/精细预览自动切换、稳定的人脸分析缓存，以及[五色色标、批量标记与组合筛选](Documentation/COLOR_LABELS.md)。98 项本机回归零失败（1 项可选模型权重未启用），已完成独立测试图库中的原生界面、重启、紧凑布局与全尺寸美颜导出验收；原图库原片、配方与选片标记核对一致。

当前提供 **186 个标量控制、RGB 四通道曲线、三向色轮、41 款内置风格与自定义 CUBE 导入**。工作台采用大画布、底部胶片条、右侧折叠参数组和功能栏；AI 助手可与照片并排显示。EditRecipe v2 是手动、AI、预设和批量的同一份状态，支持 v1 迁移、撤销/重做、分组重置及 AI 参数锁。逐项能力见 [专业工作台](Documentation/PRO_EDITOR.md)。

选片支持星标/旗标/五色色标、组合筛选和排序；**13 组参数同步与整组撤回**保留目标锁，批量可按统一配方、每张已存设置或逐张 AI 方案导出。步骤见 [选片与同步](Documentation/PIXCAKE_WORKFLOW.md)。最终使用入口为 `Deliverables/LumaStudio.app`，历史包按版本保留。

在线模型、MetalPetal GPU 美颜、Mac 听写和小智接口继续保留。右上角网络图标打开接入设置，详见 [接入说明](Documentation/INTEGRATIONS.md)。API 密钥只存系统钥匙串或本次会话内存；默认不上传照片。当前源码仓库：[shichenghaoshu/LumaStudio](https://github.com/shichenghaoshu/LumaStudio)。仓库目前公开，只含审查后的源码、许可及运行库；不含商业计划书、逆向私有资料、个人照片、凭据或 GGUF 权重。跨平台客户端含一张有来源记录的 CC0 风景示例。

新增 [Agent 处理过程页面](Documentation/AGENT_PROCESS.md)：实时执行步骤、阶段耗时、真实预览、逐轮指标与版本采用；入口位于修图页顶部“处理过程”及助手面板。界面改造和实际检查见 [Mac 工作区](Documentation/UI_WORKSPACE.md)；新增功能和未完成的训练工作见 [Edge AI 当前状态](Documentation/EDGE_AI.md)；训练工具见 [Training/README.md](Training/README.md)。当前 Qwen 1.5B 是通用基础模型，尚未进行 LumaStudio 专业任务训练。

**实际边界：** 第一代 G9 的真实 RW2 样片已解码并全分辨率导出；G9 实机拍摄尚未验收。美颜使用 MetalPetal 高通平滑、强效磨皮与 Vision／传统皮肤蒙版，新增瓷白、红润及关键点引导的瘦脸、大眼；纹理可降至 0，高强度预设允许夸张效果。没有捆绑训练好的商业精修网络。0.4.2 的 DeepSeek 真实连接、单张修图和 8 张独立 RAW 的逐张在线批处理已通过，全部无本地回退；原片哈希保持不变。小智仍仅有本机协议验证，真人语音识别质量未验收。不同机型、压缩方式和系统版本仍须逐文件检查，不能保证所有历史或未来格式。

Mac 性能更新采用细粒度 Observation、后台 RAW 能力探测、有界缓存和 960px 交互/1600px 精细预览。M2 Pro、同一公开人像、Release 构建，强磨皮精细预览热中位数从 48.6ms 降至 23.4ms，交互 9.8ms；加塑形为 48.9→23.8ms，交互 9.7ms。最终精细输出与旧流程逐像素一致。这是图像引擎观测，实际界面还包含调度与显示耗时，不能作为界面帧率或所有设备保证。

Android / Windows 目前提供可离线运行的图库、24 个基础参数、8 色 HSL、30 款原创滤镜、撤销/重做、逐张保存、中心裁切与批量导出。**平台功能范围不同**：完整 186 项专业控制、局部蒙版、16 位/ICC 输出、本地 Qwen 和语音/相机接口仍在 Mac。Portable 配方与 Mac 配方暂不互通。详情见上述客户端文档。

## 开始使用

1. 在 `Deliverables` 中打开 `LumaStudio.app`（Mac 本机临时签名版），或用 Xcode 打开 `LumaStudio.xcodeproj`。
2. **修图**：导入照片/文件夹，在右侧调色、人像、局部、滤镜、RAW、裁剪、预设和导出页操作。调色页可展开白平衡、影调、色阶、曲线、HSL、色彩编辑器、颜色分级、可选颜色、细节、颗粒、暗角及校准；提供精确输入、滑块、重置和 AI 锁。顶部“AI 助手”开启与照片并排的对话，“精细调整”回到同一份参数。顶部过程图标查看真实执行步骤与逐轮指标；底部提供原图/分屏对照、星标筛选和参数同步。菜单“工作区”可切换紧凑与标准布局。
3. **拍摄**：可使用厂商联机软件将照片保存到监听目录；原有 G9 路径使用官方 LUMIX Tether，选择 PC(Tether)。默认目录为 `~/Pictures/LumaStudio/Inbox`。本应用监听稳定的新文件并复制原件到图库、生成缩略图、可自动美颜。内嵌实时取景不可用，需在 Tether 中取景。
4. **批量**：在批量页勾选照片，选择“统一当前配方”、“每张已存设置”，或选择“逐张 AI 调整”输入同组要求；后者逐张分析、生成独立方案、检查并导出，保留各张照片的锁定值与当前模板锁。计划、来源与失败原因保存在队列日志；可把本张方案载入编辑器并撤销。默认输出到图库 Exports，菜单中可另选文件夹。暂停在当前照片处理完成后生效；取消会等待当前写入任务退出。
5. **模型**：点击右上角芯片图标安装、切换或卸载本地模型包。当前这台 Mac 已安装本地 Qwen 1.5B 基础模型；没有可用模型或输出检查失败时使用本地规则。风格只在点击“记住这个风格”后保存在本机。
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
- `Packages/PluginKit` / `Tools/PluginCommunity`：四类声明式插件、不可变版本安装、统一执行器和本机创作社区。
- `Packages/CloudModel`：URLSession 在线规划、两种 API 格式、钥匙串凭据、严格配方与图片上传约束。
- `Packages/VoiceBridge`：小智 MCP WebSocket、loopback HTTP、最终文字与有界去重；`Tools/VoiceMCP`：可选 stdio 适配器。
- `Packages/ColorEngine`：41 个内置 LUT（30 个原有风格及 11 个徕卡／哈苏／富士方向独立仿色）、CUBE 导入、RGB 色阶与可选颜色、Lab、直方图、参考色彩档案与肤色保护。来源、许可和验证范围见 [相机仿色说明](Documentation/CAMERA_COLOR_LOOKS.md)。
- `Packages/PhotoPipeline`：ImageIO / CIRAWFilter + LibRaw 0.22.3 备用显影、Metal Core Image context、分级处理、预览缓存、非覆盖导出。
- `Packages/BatchEngine`：有限并发、逐张独立 AI 方案、计划持久化与复用、暂停/继续/取消、重试、任务 JSON 恢复。
- `Packages/LocalLibrary`：SwiftData ModelActor、本地索引、SHA256 去重、原片副本和 RAW/JPEG 配对。
- `Packages/LocalSync`：Bonjour、TLS-PSK、Keychain 配对、分块与完整性校验、受能力限制的远程快门。
- `Tests`：共享模块的单元及集成测试；`Tools/LumaDiagnostics`：真实样片与性能验证工具。
- `Resources`：自制图标、原创 LUT 生成定义、示例配方；没有未授权模型或商业素材。

## 验证与未完成项

当前 Mac 收束记录见 [0.5.4 中式美颜与交付](Documentation/CHINESE_BEAUTY_0.5.4.md)。[0.5.3](Documentation/RELEASE_0.5.3.md)、[0.5.1](Documentation/RELEASE_0.5.1.md)、Windows / Android 的 [0.5.0](Documentation/RELEASE_0.5.0.md)、[0.4.2](Documentation/RELEASE_0.4.2.md)、[早期验收记录](Documentation/VALIDATION.md)、[早期性能报告](Documentation/PERFORMANCE.md) 与 [历史逐项状态](Documentation/STATUS.md) 保留为历史阶段证据。原始日志和输出位于 `Artifacts`，公开验证包只选择审查后的记录与公开素材输出。

G9 实机、M1 真机、M 系列实体 iPad、跨实体设备传输、100 张不同场景的连续运行、专业人像主观质量评审仍需完成。该版本没有 G9 内嵌实时取景、拍摄参数调节、G9 直接 Wi-Fi 控制、任意液化、完整五官/身体重塑或自动内容填补；这些入口明确禁用或未开放。
