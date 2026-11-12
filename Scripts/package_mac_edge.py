#!/usr/bin/env python3
"""Package the verified Mac build and source. Preserve old Pad/0.1 artifacts as legacy."""
from pathlib import Path
import hashlib
import json
import os
import plistlib
import re
import shutil
import stat
import subprocess
import zipfile

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/"Deliverables"

def sha(path):
    with path.open("rb") as stream:return hashlib.file_digest(stream,"sha256").hexdigest()

def archive_source(destination):
    allowed=["Package.swift","Package.resolved","README.md",".gitignore",".github","LumaStudio.xcodeproj","Apps","Packages","Resources","Tests","Tools","Scripts","Documentation","Training","Vendor/llama-runtime.xcframework","Vendor/llama-LICENSE.txt","Vendor/Notices","Vendor/runtime-provenance.json","Models/manifests"]
    excluded={".venv","__pycache__",".DS_Store","xcuserdata"}
    with zipfile.ZipFile(destination,"w",zipfile.ZIP_DEFLATED,compresslevel=6) as archive:
        for name in allowed:
            root=ROOT/name
            for path in sorted(root.rglob("*") if root.is_dir() else [root]):
                if excluded.intersection(path.parts) or path.suffix in [".pyc",".gguf",".pdf",".docx"] or any(part in {"data","outputs"} for part in path.relative_to(ROOT).parts[:2]) or path.name.startswith(".env"):continue
                relative="LumaStudio/"+path.relative_to(ROOT).as_posix()
                if path.is_symlink():
                    info=zipfile.ZipInfo(relative);info.create_system=3;info.external_attr=(stat.S_IFLNK|0o777)<<16
                    archive.writestr(info,os.readlink(path))
                elif path.is_file():archive.write(path,relative)

def main():
    build=(ROOT/"Artifacts/integrations-mac-build.log").read_text()
    tests=(ROOT/"Artifacts/integrations-tests.log").read_text()
    if "** BUILD SUCCEEDED **" not in build or "** BUILD FAILED **" in build:raise RuntimeError("Mac build not verified")
    if "Executed 60 tests, with 0 failures" not in tests or "unexpected signal" in tests:raise RuntimeError("Current shared checks not passed")
    stdio=(ROOT/"Artifacts/integrations-stdio-tests.log").read_text()
    if "Ran 3 tests" not in stdio or not stdio.rstrip().endswith("OK"):raise RuntimeError("Voice stdio checks not passed")
    acceptance=json.loads((ROOT/"Artifacts/integrations-acceptance.json").read_text())
    if acceptance.get("status")!="passed":raise RuntimeError("Current UI acceptance not passed")
    stage=ROOT/"work/delivery-mac-edge"
    if stage.exists():shutil.rmtree(stage)
    stage.mkdir(parents=True)
    source=ROOT/"ReleaseData/Build/Products/Release/LumaStudioMac.app"
    app=stage/"LumaStudio.app"
    subprocess.run(["ditto",str(source),str(app)],check=True)
    subprocess.run(["codesign","--verify","--deep","--strict",str(app)],check=True)
    version=plistlib.loads((app/"Contents/Info.plist").read_bytes())["CFBundleShortVersionString"]
    if version!="0.3.0" or acceptance.get("version")!=version:raise RuntimeError("Wrong app version")
    binary=app/"Contents/MacOS/LumaStudioMac"
    if acceptance.get("executable_sha256")!=sha(binary):raise RuntimeError("UI acceptance does not match current executable")
    subprocess.run(["ditto","-c","-k","--sequesterRsrc","--keepParent",str(app),str(stage/"LumaStudio-macOS.zip")],check=True)
    archive_source(stage/"LumaStudio-source.zip")
    evidence=["agent-process-build.log","agent-process-tests.log","agent-process-acceptance.json","agent-process-empty.png","agent-process-running.png","agent-process-result.png","agent-process-comparison.png","agent-process-plan.png","agent-process-compact.png","agent-process-cancelled.png","agent-process-ax.txt","agent-process-export-ax.txt","mac-ui-build.log","mac-ui-acceptance.json","mac-ui-before.png","mac-ui-editor.png","mac-ui-compare.png","mac-ui-compact.png","mac-ui-portrait.png","mac-ui-recipe.png","mac-ui-assistant.png","mac-ui-raw.png","mac-ui-batch.png","mac-ui-batch-ax.txt","mac-ui-export-ax.txt","mac-ui-assistant-ax.txt","edge-tests-acceptance.log","edge-agent-tests-latest.log","edge-release-mac.log","edge-release-package.log","training-tests.log","training-sft-smoke.log","training-preflight.json","teacher-workflow.log","TeacherWorkflow/summary.json","TrainingSmoke/SMOKE-RESULT.json","EdgeOfflineFinal/measurement.json","EdgeOfflineFinal/stdout.json","EdgeOfflineFinal/stderr.log"]
    evidence += [p.relative_to(ROOT/"Artifacts").as_posix() for p in sorted((ROOT/"Artifacts").glob("integrations-*")) if p.is_file()]
    evidence += [p.relative_to(ROOT/"Artifacts").as_posix() for p in sorted((ROOT/"Artifacts/IntegrationsBeauty").glob("*")) if p.is_file()]
    with zipfile.ZipFile(stage/"LumaStudio-validation.zip","w",zipfile.ZIP_DEFLATED) as archive:
        for item in evidence:
            path=ROOT/"Artifacts"/item
            if path.is_file():archive.write(path,"Artifacts/"+item)
    manual="""# LumaStudio Mac 0.3.0

打开 LumaStudio.app，导入照片。右侧有调色／人像／配方／助手面板；画布可缩放、原图对照，顶部可打开 Agent 处理过程。处理完成后由你确认导出，原片始终保留。新增美颜使用真实 MetalPetal GPU 算法，结合皮肤区域和纹理保护，不是训练好的商业精修网络。

左侧「接入 → 在线模型」可选择通义、DeepSeek、OpenAI 或兼容服务：填写 Base URL、模型 ID、自己的密钥，保存并测试，再切换为在线模型。密钥只进系统钥匙串；默认不上传照片，可主动开启 512 像素小预览。当前本机未配置真实付费服务密钥。

「接入 → 语音与小智」可保存自己的小智 MCP 接入点并连接；默认语音文字进入待处理列表。也可启动仅本机的认证 HTTP 接口，复制端口和令牌供其他语音 AI 使用。助手及处理过程有 Mac 麦克风听写按钮，默认设备端识别。完整说明、请求例子和 stdio 接法见源码 Documentation/INTEGRATIONS.md；真人朗读与官方小智服务尚未实连验收。

本机已有 Qwen 1.5B 基础模型；源码和 App 压缩包不含约 986 MB 权重。没有本地模型时可用规则，或配置自己的在线模型。App 核心功能无需 Python／Ollama。Qwen 基础模型没有完成 LumaStudio 专业蒸馏。

私有源码仓库：https://github.com/shichenghaoshu/LumaStudio 。不包含商业计划书、逆向目录、私有照片、密钥或 GGUF 权重。训练入口见 Training/README.md；正式 1.5B／3B 训练、Jarvis 对照基准和专业盲评未执行。

本包是 macOS 14+ Apple Silicon 本机临时签名开发版，未经 Developer ID 公证。iPad 暂缓，G9 实机尚未验收。60 项 Swift 测试、3 项 stdio 协议测试和真实人像导出已通过；在线模型／小智界面检查使用本机协议测试服务，不代表真实供应商或语音硬件验收。
"""
    (stage/"使用说明.md").write_text(manual)
    lines=["LumaStudio Mac 0.3.0 (5) · local development delivery · 2026-11-12","macOS 14+ arm64; local ad-hoc signature; no Developer ID notarization","Current Mac Release: SUCCEEDED; current native UI acceptance: passed","Current shared Swift checks: 60 / 0 failures; stdio MCP protocol: 3 / 0 failures","Actual MetalPetal GPU portrait + exposure/warmth regression and 2615x3269 JPEG export passed","Cloud API / XiaoZhi UI: LOCAL protocol fixtures; real paid API, official XiaoZhi and physical speech quality: NOT RUN","Prior training checks: 6 passed; synthetic tiny SFT smoke: 2 steps; product Student models trained: 0","Source: https://github.com/shichenghaoshu/LumaStudio (private); source excludes photos, research and weights","iPad deferred; legacy Pad artifacts are not part of this delivery",""]
    for path in sorted(stage.glob("*.zip")):lines.append(f"{path.name}: {path.stat().st_size} bytes; SHA256 {sha(path)}")
    binary=app/"Contents/MacOS/LumaStudioMac";lines.extend(["",f"Mac executable SHA256: {sha(binary)}","Model weights are separate; existing local Qwen base is NOT a trained LumaStudio Student."])
    (stage/"MANIFEST.txt").write_text("\n".join(lines)+"\n")
    OUT.mkdir(exist_ok=True)
    previous=OUT/"LumaStudio.app/Contents/Info.plist"
    old_version=plistlib.loads(previous.read_bytes()).get("CFBundleShortVersionString","unknown") if previous.exists() else "unknown"
    legacy=OUT/("Legacy-"+old_version);legacy.mkdir(exist_ok=True)
    for path in list(stage.iterdir()):
        destination=OUT/path.name
        if destination.exists():
            saved=legacy/path.name
            if not saved.exists():destination.rename(saved)
            elif destination.is_dir():shutil.rmtree(destination)
            else:destination.unlink()
        path.rename(destination)
    print("\n".join(lines))

if __name__=="__main__":main()
