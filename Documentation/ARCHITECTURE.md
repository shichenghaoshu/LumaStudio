# 架构与数据流

> 本文记录原 0.1 基础能力；本轮 Mac 0.2 Edge AI 的新增功能、模型真实状态和剩余工作以 [EDGE_AI.md](EDGE_AI.md) 为准。iPad 后续开发和验收已按用户要求暂缓。

两个 Xcode App targets 链接同一个本地 SPM PhotoCore。根 Package 中的十一模块有明确依赖方向，第三方依赖为零。Mac 专属 ImageCaptureCore 实现用 `#if os(macOS)` 隔离，不要求 iPad 提供 macOS 的 tethering API。

## 导入与原片

文件监听使用 DispatchSource 文件系统事件，加一秒轮询以弥补漏报、目录删除/重建和设备断连。文件必须三次尺寸/修改时间一致，且静止至少两秒。失败五秒后重试，只有处理器确认成功才记录已处理状态。

导入采用“源文件 → .staging 副本 → 校验写入前后属性 → SHA256 → ImageIO 完整状态及缩略图 → Originals → SwiftData 提交”。图库文件以内容 SHA256 命名，避免同名覆盖。相同字节不会重复创建照片；同名不同内容保留为新照片。同目录同 stem 的 RAW/JPEG、修改时间相差不足 15 秒且类型互补时配对；RAW 成为主文件，JPEG 保留为伴随文件。跨目录、跨日期或多对一的模糊情况不自动合并。

SwiftData 使用 ModelActor / DefaultSerialModelExecutor；应用从后台任务初始化，导入、哈希、元数据不会在 SwiftUI 主执行器上完成。CloudKit 显式为 `.none`。数据库只记录文件位置、哈希和编辑参数。

## 三级图像处理

- Thumbnail：ImageIO 内嵌/下采样缩略图，最大 360 px，导入后存磁盘。
- Preview：CIRAWFilter scaleFactor 或 ImageIO 下采样，最长边 1600 px。将预览物化到独立的 sRGB 图像，避免每次拖动滑块重新解码 RAW。最多缓存两张预览；人脸/遮罩只缓存当前照片与 RAW 参数组合。
- Full resolution：重新从原片构建原生大小、色彩管理的 Core Image 图。没有使用预览冒充最终输出；JPEG/PNG 为 sRGB，TIFF 为 16 位 RGBA sRGB。

Metal 可用时显式创建 MTLDevice 和 CIContext；没有设备时 Core Image 软件后备。Core Image 负责延迟求值和 GPU 调度。自定义的两个紧凑 CIColorKernel 用于纹理恢复和肤色均匀；当前仍使用系统兼容的 Core Image kernel source 编译接口，其弃用警告被记录，后续可转成预编译 Metal kernel，无需改变算法接口。

RAW 参数使用当前 SDK 实际存在的 exposure、neutralTemperature、neutralTint、boostShadowAmount、受支持时的 localToneMapAmount。没有编造专用 highlightRecovery API；高光处理依赖系统 RAW 解码及局部影调映射，无法恢复传感器已剪裁信息。

## 自然美颜

Vision face landmarks → 320 px 人脸/颈部几何限制 → 个人脸颊色度采样与肤色概率 → 眼睛/眉毛/嘴唇排除 → guided filter 遮罩精炼 → 低频降噪 → 恢复约 94% 高频残差 → 仅皮肤区域融合。

guided filter 以单通道亮度为 guide，积分图计算局部均值，复杂度 O(width × height)。低频平滑使用 Core Image 的边缘保留降噪，最终输出恢复原图高频；未将整脸高斯模糊作为最终美颜。红色且局部偏暗的小异常只做保守衰减，不承诺语义识别痣/雀斑或完整祛痘。

默认没有神经网络权重。可选模型失败会明确回退到 Vision + 传统分割。算法对毛发、特殊光照、多种肤色和遮挡仍需更大测试集评估。

## 色彩与配方

六个原创 17³ LUT 作为包内资源。参考图片保存 Lab 均值、标准差、64-bin 亮度直方图及影调估计。每张源照片独立分析，使用受限的 Reinhard 风格 Lab 统计迁移，加 25% 亮度分位匹配，生成确定性 LUT。人脸皮肤区域恢复 80% 原有色彩，之后与用户强度混合。这里的色温/曝光分析是图像估计，不代表测量仪器或相机白平衡真值。

ColorProfile 保存参考分布；Recipe 保存参数和 profile ID。导出的 .cube 对当前源照片适配，批量使用 ColorProfile 时逐张重算。仅 .cube 无法携带空间人脸遮罩，因此外部软件使用导出 LUT 不具备本应用的局部肤色保护。JSON profile 应与引用它的 Recipe 一同分享。

## 队列与恢复

批量最大两个 worker（低内存/部分 iPad 场景一个），每张完成释放处理上下文，禁止一次性加载所有原片。暂停不派发下一张，当前图像继续到安全边界；取消使派发和写入任务检查 cancellation，等待任务退出，清理临时文件。每次状态改变写原子 JSON 日志。恢复时 running 还原 pending，并停在 paused 状态，用户选择继续。已完成项目不自动重复导出。

导出先写同目录临时文件，然后以不允许覆盖的 move 提交。路径检查解析最近存在的父目录，防止符号链接绕回 Originals；即使发生文件名竞争也会报错而不覆盖。

## 本地同步

Bonjour `_lumastudio._tcp` 发现 → 二维码/链接带 256-bit 随机密钥 → Keychain 本机保存 → Network.framework TLS 1.2 PSK + AES-128-GCM → 128 KiB 分块，每块确认 → 文件大小、偏移和 SHA256 校验 → 原子提交 → 图库导入。

传输最长 2 GiB；帧最长 512 KiB，文件名限制为安全的照片 basename。单连接、单文件在途提供背压。接收端保留会话目录与原始文件名，避免 RAW/JPEG 名称被随机前缀破坏。只允许已验证原生快门的 Host 宣告远程拍摄能力，连接断开立刻撤回能力。

初版是每个 Host 一组共享配对密钥，可撤销全部配对，尚未实现每台设备单独撤销。链接首次使用在客户端检查 15 分钟有效期，配对密钥持续有效到 Host 撤销；二维码应视为密码保密。该实现没有被第三方安全审计。
