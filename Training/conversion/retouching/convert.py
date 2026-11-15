from pathlib import Path
import json, time, hashlib, shutil
import torch
import coremltools as ct
from upstream.unet_deploy import UNet
from upstream.detection_model.detection_unet_in import DetectionUNet
from upstream.inpainting_model.inpainting_unet import RetouchingNet

import argparse, urllib.request
ROOT=Path(__file__).resolve().parent
parser=argparse.ArgumentParser(description='Convert verified Apache-2.0 portrait retouching weights into bundled local Core ML components.')
parser.add_argument('--weights-dir',type=Path,required=True)
parser.add_argument('--output',type=Path,required=True)
parser.add_argument('--download',action='store_true',help='Download the two public, pinned ModelScope weights and verify SHA-256.')
args=parser.parse_args()
torch.set_num_threads(4)
weights=args.weights_dir;weights.mkdir(parents=True,exist_ok=True)
out=args.output;out.mkdir(parents=True,exist_ok=True)
WEIGHTS=[('pytorch_model.pt','72b82f86fb9720b0e2adf05be0a0ea47cc6f329d','760d0c0b95c4e0a692165677fe2b82dbdf8fbbd4a3780ca966599c627b082993'),('joint_20210926.pth','b84ee0341a26f9cf440a47ba38133ed181fd51b1','c9e1388b19d9334c90db08308c86de208f535920ee381ae8a9cb63484a78351a')]
for name,revision,digest in WEIGHTS:
    path=weights/name
    if not path.exists() and args.download:
        url='https://www.modelscope.cn/api/v1/models/iic/cv_unet_skin-retouching/repo?Revision='+revision+'&FilePath='+name
        with urllib.request.urlopen(url,timeout=60) as source,path.with_suffix('.partial').open('wb') as target:
            shutil.copyfileobj(source,target)
        path.with_suffix('.partial').replace(path)
    if hashlib.sha256(path.read_bytes()).hexdigest()!=digest:raise RuntimeError('Upstream weight SHA-256 mismatch: '+name)

joint=torch.load(weights/'joint_20210926.pth',map_location='cpu',weights_only=True)
blend=UNet(3,3,init_weights=False);blend.eval()
blend.load_state_dict(torch.load(weights/'pytorch_model.pt',map_location='cpu',weights_only=True)['generator'])
detect=DetectionUNet(3,1,init_weights=False);detect.eval();detect.load_state_dict(joint['detection_net'])
heal=RetouchingNet(4,3,init_weights=False);heal.eval();heal.load_state_dict(joint['inpainting_net'])

class Detector(torch.nn.Module):
    def __init__(self):super().__init__();self.net=detect
    def forward(self,x):return torch.sigmoid(self.net(x))

class Healer(torch.nn.Module):
    def __init__(self):super().__init__();self.net=heal
    def forward(self,image,keep):
        # RGB correction in gamma-encoded sRGB, localized to detected blemishes.
        masked=image*keep
        return (self.net(masked,keep)-image)*(1-keep)*.5

def image_input(n):return ct.ImageType(name='image',shape=(1,3,n,n),scale=1/127.5,bias=[-1,-1,-1],color_layout=ct.colorlayout.RGB)
models=[('LumaRetouchBlend',blend,[torch.zeros(1,3,512,512)],[image_input(512)],'blend'),
        ('LumaBlemishDetect',Detector().eval(),[torch.zeros(1,3,768,768)],[image_input(768)],'probability'),
        ('LumaBlemishHeal',Healer().eval(),[torch.zeros(1,3,576,576),torch.ones(1,1,576,576)],[image_input(576),ct.TensorType(name='keep',shape=(1,1,576,576))],'correction')]
receipt=[]
for name,net,example,inputs,output in models:
    start=time.perf_counter()
    with torch.no_grad():traced=torch.jit.trace(net,example)
    ml=ct.convert(traced,inputs=inputs,outputs=[ct.TensorType(name=output)],minimum_deployment_target=ct.target.macOS13,convert_to='mlprogram',compute_precision=ct.precision.FLOAT16)
    ml.author='Alibaba, Inc. and its affiliates; Core ML adaptation by LumaStudio'
    ml.license='Apache-2.0'
    ml.short_description='Local portrait retouching component from iic/cv_unet_skin-retouching. No training performed by LumaStudio.'
    ml.user_defined_metadata['source']='https://www.modelscope.cn/models/iic/cv_unet_skin-retouching'
    ml.user_defined_metadata['role']=output
    ml.save(str(out/(name+'.mlpackage')))
    files=[{'path':str(p.relative_to(out)),'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted((out/(name+'.mlpackage')).rglob('*')) if p.is_file()]
    receipt.append({'model':name,'seconds':time.perf_counter()-start,'files':files})
    print(name,'saved',sum(f['bytes'] for f in files),'bytes',flush=True)
(out/'conversion.json').write_text(json.dumps(receipt,indent=2))
