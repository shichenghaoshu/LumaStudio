"""Report readiness without downloading weights, training, or inventing measurements."""
import importlib.util
import json
import platform
from pathlib import Path
from Training.common import ROOT,atomic_json

def main():
    modules={name:importlib.util.find_spec(name) is not None for name in ["torch","transformers","peft","accelerate","trl","coremltools","mlx"]}
    resources={"python":platform.python_version(),"machine":platform.machine(),"modules":modules}
    if modules["torch"]:
        import torch
        resources.update(torch_version=torch.__version__,cuda_available=torch.cuda.is_available(),cuda_devices=torch.cuda.device_count(),mps_available=torch.backends.mps.is_available())
    report={"environment":resources,"native_renderer_exists":(ROOT/".build/release/LumaAgentCLI").exists(),
            "full_student_sft":"NOT RUN","full_student_distillation":"NOT RUN","human_preference_optimization":"NOT RUN",
            "specialist_training":"NOT RUN","quantization_comparison":"NOT RUN","coreml_numerical_parity":"NOT RUN",
            "jarvisart_benchmark":"NOT RUN","reason":"User has no GPU training server; current delivery scope is Mac application and reproducible training pipeline."}
    atomic_json(ROOT/"Artifacts/training-preflight.json",report);print(json.dumps(report,ensure_ascii=False,indent=2))
if __name__=="__main__":main()
