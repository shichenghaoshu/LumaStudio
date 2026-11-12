"""Training tools are separate from the native application's runtime."""
import os
os.environ.setdefault("HF_HUB_DISABLE_TELEMETRY","1")
os.environ.setdefault("WANDB_DISABLED","true")
