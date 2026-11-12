"""Training-only transport for a GPU teacher; never imported or shipped by the Mac application."""
import base64
import json
import os
from urllib.parse import urlparse
from urllib.request import Request,urlopen
from Training.common import validate_recipe
from Training.teachers.provider import TeacherProvider

class RemoteVisionTeacher(TeacherProvider):
    name="remote-qwen25-vl-training-teacher"
    training_authorized=True
    quality_tier="teacher_candidate"
    def __init__(self,endpoint):
        parsed=urlparse(endpoint)
        if parsed.scheme!="https" and not (parsed.scheme=="http" and parsed.hostname in ["127.0.0.1","localhost","::1"]):
            raise ValueError("Use HTTPS or an SSH-forwarded loopback teacher endpoint")
        if parsed.username or parsed.password:raise ValueError("Do not embed credentials in a URL")
        self.endpoint=endpoint.rstrip("/")
        self.token=os.environ.get("LUMA_TRAINING_TOKEN")
        if not self.token:raise ValueError("Set LUMA_TRAINING_TOKEN in the research environment")
    def propose(self,image,instruction,analysis):
        body=json.dumps({"protocol_version":1,"image_base64":base64.b64encode(image.read_bytes()).decode(),"instruction":instruction,"analysis":analysis}).encode()
        if len(body)>8*1024*1024:raise ValueError("Preprocessed teacher image is too large")
        request=Request(self.endpoint+"/v1/recipe",data=body,headers={"Content-Type":"application/json","Authorization":"Bearer "+self.token},method="POST")
        with urlopen(request,timeout=180) as response:
            result=json.loads(response.read(128*1024))
        recipe=result["recipe"];validate_recipe(recipe);return recipe
