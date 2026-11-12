"""Loopback GPU teacher endpoint, intended for an SSH tunnel from the Mac renderer."""
import argparse
import base64
import hmac
import json
import os
import tempfile
from http.server import BaseHTTPRequestHandler,HTTPServer
from pathlib import Path
from Training.teachers.provider import HuggingFaceVisionTeacher

def main(args):
    token=os.environ.get("LUMA_TRAINING_TOKEN")
    if not token:raise RuntimeError("LUMA_TRAINING_TOKEN is required; it is never saved in dataset records")
    teacher=HuggingFaceVisionTeacher(args.model,args.allow_download)
    class Handler(BaseHTTPRequestHandler):
        def log_message(self,*args):pass
        def do_POST(self):
            try:
                if self.path!="/v1/recipe":self.send_error(404);return
                if not hmac.compare_digest(self.headers.get("Authorization",""),"Bearer "+token):self.send_error(401);return
                length=int(self.headers.get("Content-Length","0"))
                if not 1<=length<=8*1024*1024:raise ValueError("Invalid request size")
                request=json.loads(self.rfile.read(length))
                if request.get("protocol_version")!=1:raise ValueError("Unsupported protocol")
                instruction=request["instruction"]
                if not isinstance(instruction,str) or not 1<=len(instruction)<=1000:raise ValueError("Invalid instruction")
                with tempfile.TemporaryDirectory(prefix="luma-training-") as directory:
                    image=Path(directory)/"teacher-input.jpg";image.write_bytes(base64.b64decode(request["image_base64"],validate=True))
                    from PIL import Image
                    with Image.open(image) as opened:
                        if opened.width*opened.height>4_194_304:raise ValueError("Use the preprocessed training image")
                        opened.verify()
                    recipe=teacher.propose(image,instruction,request["analysis"])
                body=json.dumps({"protocol_version":1,"teacher":teacher.name,"recipe":recipe},allow_nan=False).encode()
                self.send_response(200);self.send_header("Content-Type","application/json");self.send_header("Content-Length",str(len(body)));self.end_headers();self.wfile.write(body)
            except Exception:
                # No photo, prompt, token, model path or exception body is echoed to the network.
                self.send_error(422,"Teacher could not produce an accepted structured recipe")
    server=HTTPServer(("127.0.0.1",args.port),Handler)
    server.timeout=180
    print(f"Training teacher listens on loopback port {args.port}; use an SSH tunnel. No app runtime dependency.",flush=True)
    server.serve_forever()

if __name__=="__main__":
    p=argparse.ArgumentParser();p.add_argument("--model",default="Qwen/Qwen2.5-VL-7B-Instruct");p.add_argument("--port",type=int,default=8765);p.add_argument("--allow-download",action="store_true");main(p.parse_args())
