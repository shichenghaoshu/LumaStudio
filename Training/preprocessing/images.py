from pathlib import Path
from Training.common import NativeRenderer

def prepare_image(image: Path, output: Path, renderer: NativeRenderer, maximum=1024):
    from PIL import Image
    output.mkdir(parents=True, exist_ok=True)
    native = output / "native-preview.jpg"
    renderer.call("preprocess", image, native)
    destination = output / "teacher-input.jpg"
    with Image.open(native) as opened:
        rgb = opened.convert("RGB")
        rgb.thumbnail((maximum, maximum))
        # A clean RGB image intentionally omits EXIF/GPS and user library paths.
        rgb.save(destination, "JPEG", quality=95, exif=b"")
    return destination
