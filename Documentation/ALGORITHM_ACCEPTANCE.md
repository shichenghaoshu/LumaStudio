# Mac 0.5.2 算法与功能实际验收

2026-11-14，Mac 0.5.2 (16) 验收候选。正式可用的公开 Mac 版仍为 0.5.1；0.5.2 尚待原生界面验收收束。此文记录实际执行范围，不是所有图片、设备或审美偏好的质量保证。

## 结果与边界

Release 优化构建实际执行 **119 项 Swift 检查，0 失败，0 跳过**（87.99 秒）；先前 Debug 完整检查117项无失败，新增检查另行通过。实际运行了本地 Qwen、真实照片、真实 GPU、真实 RAW、旧数据库迁移和本机 TLS／语音 HTTP。语音 MCP stdio 另外3项通过；训练流水线在已配置的Python环境中6项通过，包含合成数据单步梯度检查，不代表已经训练产品模型。

从实际 `ParameterCatalog` 导出 **184 项标量**，逐项建立证据：

- **169 项非 RAW 图像参数**：通过已知灰阶、色块、噪声、边缘、几何标记或已知皮肤蒙版，检查方向、通道隔离、空间位置或清晰定义的效果；全部存在对应的通过记录。不是只判断“像素不同”。
- **3 项输出参数**：实际检查JPEG质量误差与大小、输出长边和DPI。30种格式／位深／ICC／EXIF组合全部通过，8种EXIF方向分别核对四角颜色。
- **11 项 RAW 控制**：本轮原生解码器声明支持并记录真实输出。锐度在G9原尺寸输出生效，在1600px预览无变化，界面提供提示。原生RAW降噪、细节恢复与摩尔纹没有对应的干净场景真值或大规模质量标注，只能认定在本轮文件上执行并产生效果。
- **1 项 RAW 局部影调**：本轮9个文件均未声明支持，按当前文件禁用，不算通过。其他相机或系统版本可能不同，不能据此伪造可用状态。

固定的单元检查不等同于每个按钮均已被人工点击。原生UI本轮曾因系统目录选择框和界面工具连续超时而中断，尚未形成0.5.2最终GUI收据。图库切换、目录导入、代表参数编辑、撤销重做、蒙版、预设、批量和导出需要在恢复后完成原生操作验收。此阻塞不作为软件算法失败，也不被算作界面通过。

## 实际修复

1. 正向高光原被原生参数上限吞掉。增加亮度加权的高光提升，正负方向的灰阶检查通过。
2. 原先磨皮强度归零会连带阻断独立肤色、美白、瘦脸与大眼。解除总门控，肤色处理独立于磨皮，已知几何和肤色方向检查通过。
3. 颜色分级平衡方向相反。正值改为偏向高光颜色，负值偏向阴影颜色；蓝阴影／红高光的方向检查通过。该方向与[Adobe的颜色分级说明](https://helpx.adobe.com/lightroom/desktop/edit-photos/edit-photos.html)一致。
4. 传统美颜备用路径的独立祛瑕在磨皮归零时失效，细节恢复参数遗漏。单独强制使用备用后端复现并修复，两项独立检查通过。
5. 导出TIFF的软件字段仍写早期0.4.0，改为稳定的LumaStudio标识，避免生成误导的旧版本元数据。

测试开发中也修正过不合适的检查夹具：自然滤镜本来应为恒等，银盐滤镜含有色调；微小脉冲在8位输出中会量化为零；非对齐L8行宽不适合用作部分测试的蒙版读取；祛瑕的红暗斑点必须在线性工作RGB中也确实更红更暗。这些测试问题没有计作产品故障。早期日志保留，最终报告只读取最后通过的合同文件。

## 真实照片与文件

5张独立公开NASA人像，包含1张7人合影，分别运行全部5个美颜预设。检查实际Vision人脸／眼点、非空皮肤区域、肤色亮度变化、强效相对自然的处理量及零蒙版背景保护。已实际查看输出对照。强效模式有明显蜡感、纹理损失和局部边界，不代表广泛主观审美评审合格。默认皮肤分割依赖Vision关键点与传统色彩模型，未提供已训练的专业皮肤网络或痘痘／痣语义识别。

9个独立相机文件：松下G9 RW2、佳能7D CR2、佳能EOS R CR3、尼康D7000 NEF、索尼ILCE-7 ARW、富士X-T2 RAF、奥林巴斯E-M1 ORF、徕卡M9 DNG、宾得K-5 PEF。全部执行解码、曝光方向检查、原尺寸JPEG批量导出并重新解码，原文件SHA256不变。富士RAF走LibRaw16位备用显影，仅开放RAW曝光，其余调整使用后续影调工具。该集合不覆盖所有RAW变体。

NASA照片只用于本地算法核查，不作为人物商业代言。来源及SHA256保存在本地`fixtures.json`，参考[NASA媒体规范](https://www.nasa.gov/nasa-brand-center/images-and-media/)。其他RAW样本及许可来源为[raw.pixls.us](https://raw.pixls.us/)。这些照片未加入源码或训练数据。

## AI、接口与硬件

真实DeepSeek关闭本地回退，未附带照片预览，以“曝光增加0.3EV，其余保留，不做美颜，不新增蒙版”运行1张公开照片，实际在线方案、渲染及导出通过，来源为DeepSeek / deepseek-flash，最终曝光0.3EV，美颜关闭，原片哈希不变，整条诊断耗时7.485秒。不能以这一条指令推断所有请求都稳定成功。其他在线供应商只验证协议与错误处理，本轮没有其真实账号执行。

本地Qwen1.5B实际推理通过，并验证严格JSON、锁定值保留、禁美颜指令、最多两轮纠偏及取消处理。它是现有基础模型运行，不是已经完成本项目专业修图蒸馏。参考图匹配是有界的色彩统计迁移，不是语义风格理解。

语音本机HTTP和MCP stdio通过真实loopback与协议检查。真人麦克风听写、小智官方平台及设备未验收。目录监听通过真实文件延迟写入与目录恢复检查，未连接真实G9进行相机控制。TLS配对、Bonjour和分块传输在同机真实网络运行，未以此宣称Mac／iPad跨设备验收。Windows／Android维持0.5.0，本轮Mac算法和GUI结论不外推。

## 复现与证据

本地证据目录为 `Artifacts/AlgorithmAcceptance`（不进入源码仓库）。交付的HTML逐项报告可按分组、名称和状态搜索，JSON清单为机器可读的完整映射。

```sh
# 使用自己的公开／获准照片及已有模型包；可选夹具缺失会明确跳过。
export LUMA_RAW_FIXTURE="$PWD/work/fixtures/G9-3219.RW2"
export LUMA_RAW_MATRIX="$PWD/work/fixtures/multi-format"
export LUMA_PORTRAIT_FIXTURE="$PWD/work/fixtures/portrait.jpg"
export LUMA_AUDIT_PORTRAITS="$PWD/work/algorithm-acceptance/portraits"
export LUMA_AGENT_MODEL_PACKAGE="$PWD/Models/mac/qwen25-coder-1.5b-base"
export LUMA_LEGACY_FIXTURE="$PWD/work/fixtures/pre-review-library-original"
export LUMA_PRO_EVIDENCE="$PWD/Artifacts/AlgorithmAcceptance/Final"
export LUMA_AUDIT_OUTPUT="$PWD/Artifacts/AlgorithmAcceptance/Contracts"
mkdir -p "$LUMA_PRO_EVIDENCE" "$LUMA_AUDIT_OUTPUT"
swift test -c release
swift run -c release LumaAgentCLI parameter-catalog > Artifacts/AlgorithmAcceptance/parameter-catalog.json
python3 Scripts/build_algorithm_acceptance_report.py
```

报告生成还需要真实在线检查、RAW矩阵和人像输出的已有收据，不会以缺失文件或模拟响应补成通过。开发测试运行日志与真实服务执行分别保留。源码包含检查代码，不包含私有照片、密钥、逆向资料或模型权重。
