# LumaStudio Training Pipeline

这是独立研发环境。Mac 应用不包含或依赖这些 Python 文件、训练依赖、教师服务或 GPU 服务器。当前用户没有 GPU 服务器；正式学生训练、蒸馏、DPO、专用模型训练与量化效果比较均为 **NOT RUN**。

## 当前已经实际运行

- CC0 G9 RAW 的 3 条规则基线指令：原始照片 → 预处理 → 配方 → Core Image 全尺寸输出 → 评价 → 记录。3 条流程成功，但只有 1 张原始照片，不是正式训练集；`eligible_training_samples` 为 **0**。
- 6 项训练代码检查。
- 微型随机模型的两步 MPS SFT 冒烟测试与适配器保存。它只证明训练入口能执行；没有得到可交付的专业 Student 权重。

证据在 `Artifacts/TeacherWorkflow`、`Artifacts/training-tests.log`、`Artifacts/TrainingSmoke/SMOKE-RESULT.json`；无真实 GPU 训练结果的字段保持 `NOT RUN`。

## 环境

使用独立 Python 3.11 环境。已经固定依赖版本，禁止将研发环境作为应用运行依赖。

```sh
cd /Users/admin/Desktop/lumastudio
uv venv --python 3.11 Training/.venv
uv pip install --python Training/.venv/bin/python -r Training/requirements.txt
Training/.venv/bin/python -m Training.evaluation.preflight
Training/.venv/bin/python -m unittest discover -s Training/tests -v
```

正式 SFT／DPO 配置针对 CUDA 服务器。`--allow-mps` 仅用于明确选择的 Mac 研究实验；没有 CUDA 时脚本不会自动宣称执行 GPU 服务器训练。MLX 没有安装或作为本产品运行依赖。

## 先运行可复现的完整数据流程

Mac 负责统一原生渲染；教师只返回参数。先构建 `LumaAgentCLI`，并按项目 fixture 下载说明准备真实样片：

```sh
swift build -c release
./Scripts/fetch_fixtures.sh
Training/.venv/bin/python -m Training.data_generation.generate \
  --input Training/datasets/cc0-workflow-baseline.jsonl \
  --output Artifacts/MyWorkflowRun \
  --renderer .build/release/LumaAgentCLI
```

输出目录必须不存在，避免覆盖先前证据。输出包括每条指令的实际照片、配方、各轮评价、源文件／成品哈希，以及 `records.jsonl`、`rejected.jsonl`、`accepted-training.jsonl`、`summary.json`。

每条输入必须包含 `sample_id`、`image`、`instruction`、`rights`。`rights` 需要 `training_allowed: true`、许可、来源与原图 SHA256。私人照片还必须有本地 `consent_record`。预处理会移除给教师的 EXIF／GPS；它不会更改原图。只有获准训练的数据才进入这条流程，应用编辑历史不会自动导入。

规则或通用 GGUF 教师模式仅用于流程基线，不会自动变为正式蒸馏数据。错误配方、无法渲染、原图变化或质量检查未通过的样本不会进入 `accepted-training.jsonl`。确定性指标无法证明审美质量，人工偏好字段不会伪造。

## 教师接口与 GPU 服务器

`teachers/provider.py` 定义 `TeacherProvider`、本地基线与 Qwen2.5-VL 适配器；后者使用原始图像与指令生成统一 EditRecipe。默认候选是 [Qwen2.5-VL-7B-Instruct](https://huggingface.co/Qwen/Qwen2.5-VL-7B-Instruct)，许可为其页面列明的 Apache-2.0。模型仍须结合所用数据和实际用途审查；用户本机没有下载或运行此教师。

教师可在训练 GPU 服务器运行。`teachers/serve.py` 默认只监听服务器回环地址；Mac 通过 SSH 转发连接。认证值从 `LUMA_TRAINING_TOKEN` 环境变量读取，不保存到源码、数据记录或日志。设置同一研究环境认证值后：

```sh
# GPU 服务器：安装研究依赖并准备教师目录后执行。
python -m Training.teachers.serve --model /path/to/audited/qwen-vl-model

# Mac：建立 SSH 转发，随后在另一终端运行数据生成。
ssh -N -L 8765:127.0.0.1:8765 user@gpu-server
Training/.venv/bin/python -m Training.data_generation.generate \
  --input /path/to/authorized-input.jsonl \
  --output Artifacts/TeacherDataset \
  --teacher remote-vision --teacher-endpoint http://127.0.0.1:8765 \
  --renderer .build/release/LumaAgentCLI
```

这些是未来训练环境的操作说明，本次没有执行远端连接、上传照片或创建服务器。教师传输只属于训练工具，最终 Mac App 不连接该服务。不支持未验证 HTTPS 或 URL 内嵌凭据。也可在具有足够资源的同一研发机器上用 `--teacher qwen-vl --teacher-model /path/to/model`。

JarvisArt／JarvisEvo 只作方法与许可研究。未复制其代码、权重、训练输出，也没有借其名字宣称完成基准。其许可中的训练限制见项目 [许可和来源说明](../Documentation/EDGE_AI.md)。

## SFT 与蒸馏

预处理只接受实际渲染、通过指标门槛且教师训练授权明确的样本；至少需要两个不同原图才能建立无原图泄漏的验证划分。该规则会拒绝本次单图规则演示数据。

```sh
Training/.venv/bin/python -m Training.preprocessing.prepare_sft \
  --input Artifacts/TeacherDataset/accepted-training.jsonl --output Training/datasets/sft-v1

# GPU 服务器执行；权重默认只从本地加载。
python -m Training.sft.train --config Training/sft/configs/mac-1.5b.json \
  --data Training/datasets/sft-v1 --output Training/checkpoints/agent-1.5b-v1
```

输入采用原生规划器导出的同一 `student_prompt`，完成部分才计算训练损失；超长 JSON 不会被截断后当作有效目标。LoRA 使用独立检查点，输出目录已存在时拒绝覆盖。训练报告记录实际优化步数、损失、设备、数据哈希、版本与 CUDA 峰值内存；视觉质量字段在没有验证时仍为 `NOT RUN`。

两个研究候选配置：

- `mac-1.5b.json`：Qwen2.5-Coder-1.5B-Instruct，当前原生 Qwen 模板的基础。
- `mac-3b-research.json`：SmolLM3-3B，使用其页面列出的 Apache-2.0 许可。中文修图能力尚未比较，原生对话模板适配也没有完成，因此不是可直接替换的发布模型。

响应与工具轨迹蒸馏通过经过实际渲染验证的教师目标执行。`distillation/losses.py` 另实现 completion mask 下的温度 KL 和可训练特征投影损失。SFT 可选 `--teacher /path/to/audited/text-teacher`；在线 logit／feature 蒸馏需要 CUDA 和相同词表。不同词表会明确拒绝对齐，改用响应／工具轨迹方案。没有把这些损失函数的梯度测试当作正式蒸馏结果。

## 人工偏好与专用模型

`preference/train_dpo.py` 读取真实 `chosen`／`rejected` 配方及对应渲染照片哈希，需要完成的人工评审标记与本地 reviewer ID。它使用冻结的 SFT 适配器作偏好参考，不会把规则评分伪造为人工选择。当前没有此类标注对，DPO 未运行。

`vision/train.py` 分别训练 Vision 与 Beauty 模型：Vision 为 skin／hair／sky／subject 多通道分割，Beauty 为独立皮肤概率模型。需要每个通道的人工确认 mask 及哈希。人脸与五官目前由 Apple Vision 提供，不能声称已训练。`evaluator/train.py` 用 16 个前后图像指标和五类人工失败标签训练小型评价器；需要真实标注。

这些模型没有得到已验证权重。网络梯度单步测试使用明确标注的合成测试张量，不作为真实摄影数据或质量证据。当前应用的默认皮肤路径仍是传统分割，评价器仍是确定性指标。

## 压缩、转换与模型包

`conversion/merge_adapter.py` 只合并有完成报告的适配器。`quantization/gguf.py` 调用单独提供、核验版本的 llama.cpp 工具，生成 FP16、BF16、Q8_0、Q4_K_M，并记录实际大小与哈希。必须在同一验证任务上测量配方有效率、指令符合、视觉效果、内存和延迟后再选精度。本次没有运行这一组对比。

安装可选 Core ML 转换依赖后，`conversion/coreml.py` 可转换训练完成的 TorchScript 专用模型。它不会把通用文本 LLM 的 Core ML 转换伪装成已经适配：LLM 的模型特定 KV cache／状态转换尚未实现，当前 Mac 替代运行路径是原生 llama.cpp。专用模型转换成功也只标记 `converted_not_accepted`，仍需数值等价与设备验收。

```sh
uv pip install --python Training/.venv/bin/python -r Training/requirements-conversion.txt
Training/.venv/bin/python -m Training.conversion.coreml \
  --model /path/to/trained/model.ts --training-report /path/to/training-report.json \
  --role beauty --output /path/to/Beauty.mlpackage
```

`model_registry/package.py` 支持 GGUF、mlmodel、mlpackage。清单必须附实际许可和来源；目录模型使用排序路径、长度和逐文件哈希形成内容校验，拒绝符号链接。Mac 管理器再次校验后安装，保留旧版本供回滚。

## 独立验收

`benchmarks/run.py` 对真实照片执行本地规划、渲染、导出并保留全部报告。`Scripts/measure_agent.py` 对原生进程施加禁止网络策略，采样 RSS、总耗时、参数生成耗时、降级情况和原图哈希。它不会用配置推断 GPU／ANE 占用率；未测字段写 `NOT MEASURED`。

Jarvis 同任务基准、专业人像盲评、32GB Mac 和其他机型尚未执行。开发进度估算不能作为这些实验的替代。
