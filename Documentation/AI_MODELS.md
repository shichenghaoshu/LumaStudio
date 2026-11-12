# AI 模型、算法与许可证

> 本文记录原 0.1 基础能力；本轮 Mac 0.2 Edge AI 的新增功能、模型真实状态和剩余工作以 [EDGE_AI.md](EDGE_AI.md) 为准。iPad 后续开发和验收已按用户要求暂缓。

## 当前交付

未捆绑、未下载任何第三方美颜/语义皮肤分割权重。`Resources/Models` 只有说明文件。当前人脸检测/关键点由 Apple Vision 系统提供，本应用默认皮肤分割是自主实现的传统算法。不能把它称为已训练的 MobileNetV3，也不能宣称等同于像素蛋糕的商业人像效果。

Core ML 的加载、缓存、Vision 推理和失败降级路径已有真实代码，系统支持在设备上推理，但没有可用模型时不会显示神经网络已启用。

## 可选模型接入契约

将拥有合法来源和使用权的模型编译成 `SkinSegmentation.mlmodelc`，放在本机 Application Support/LumaStudio/Models 下，重新启动应用。Mac 实际路径通常为 `~/Library/Application Support/LumaStudio/Models/SkinSegmentation.mlmodelc`；iPad 位于应用容器相应目录，开发阶段通过 Xcode 管理。

模型应以 256×256 或 320×320 的 RGB 图像为输入，输出同方向、单通道 0...1 的皮肤概率图（8-bit / float16 / float32 pixel buffer）。当前适配器不接受多类别 label map 或 MLMultiArray 输出；需要转换为上述图像接口。分割结果仍与 Vision 五官保护相交，避免误伤眼睛与唇部。加载和推理失败会在结果状态中显示传统算法后备。

目标不超过 15 MB，优先 FP16，量化需独立验证精度、各肤色召回率及 ANE 可用性。没有为未提供的模型编造性能数据。

## 后续训练需求

优先考虑 MobileNetV3-Small 编码器与轻量 decoder。训练前需建立经授权的人像数据集，注明摄影授权、个人肖像/隐私授权、商业使用范围、再分发和衍生模型限制。标注皮肤、头发、眼眉、唇、衣物、背景；颈部单独抽检。禁止将来历不明的人脸图像或权重直接加入应用。

需有覆盖深浅肤色、彩光/逆光、遮挡、眼镜、面部毛发、多人和高 ISO 的独立验证集。训练/转换在开发阶段完成，App 不包含训练框架。合法权重准备后用 coremltools 转换固定图像输入和单通道输出，做 FP16 优化，比较转换前后 mask IoU、五官误覆盖和设备延迟；记录具体版本、转换命令、SHA256、来源链接及许可证文本，再决定启用。

## 当前素材和算法清单

- Apple Vision / Core ML / Core Image / Metal：操作系统框架，遵循 Apple 开发者与 SDK 许可；没有复制系统模型权重。
- 六个 LUT：本项目原创、确定性曲线与通道变换，由 ColorEngine 包内 `.cube` 提供，不是商业 LUT。
- 图标：本项目 Core Graphics / AppKit 绘制的原创光圈图形。
- Guided filter：依据 [He, Sun, Tang 原论文](https://kaiminghe.github.io/publications/eccv10guidedfilter.pdf)的局部线性方程自主编写 Swift 积分图实现，没有复制其 Matlab 源码。
- Lab 均值/方差迁移：借鉴 [Reinhard et al., Color Transfer between Images](https://doi.org/10.1109/38.946629) 的公开方法，当前实现是在 CIE Lab 中的受限变体，附加亮度分位与空间肤色保护。
- 皮肤概率、局部红色异常、纹理恢复：本项目的可解释算法，不使用未经授权的 PixCake 代码或资产。
- 测试 RW2：raw.pixls.us #3219，来源页列 CC0，SHA256 见 VALIDATION.md，仅开发测试目录，未随应用打包。
- 测试人像：NASA/JSC Eileen Collins S99-00858 公开照片，出处 [NASA 图片页](https://www.nasa.gov/image-detail/amf-s99-00858/)，用于本地 QA，未随应用打包，不表示 NASA 对产品背书。
