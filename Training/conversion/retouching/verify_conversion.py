"""Compare each bundled Core ML component against its exact PyTorch reference."""
from pathlib import Path
import argparse, json, time
import numpy as np
from PIL import Image
import torch
import coremltools as ct
from upstream.unet_deploy import UNet
from upstream.detection_model.detection_unet_in import DetectionUNet
from upstream.inpainting_model.inpainting_unet import RetouchingNet

p=argparse.ArgumentParser()
p.add_argument('--weights-dir',type=Path,required=True)
p.add_argument('--models-dir',type=Path,required=True)
p.add_argument('--image',type=Path,required=True)
p.add_argument('--output',type=Path,required=True)
a=p.parse_args();torch.set_num_threads(4)
joint=torch.load(a.weights_dir/'joint_20210926.pth',map_location='cpu',weights_only=True)
blend=UNet(3,3,init_weights=False);blend.eval();blend.load_state_dict(torch.load(a.weights_dir/'pytorch_model.pt',map_location='cpu',weights_only=True)['generator'])
detect=DetectionUNet(3,1,init_weights=False);detect.eval();detect.load_state_dict(joint['detection_net'])
heal=RetouchingNet(4,3,init_weights=False);heal.eval();heal.load_state_dict(joint['inpainting_net'])
original=Image.open(a.image).convert('RGB');receipt=[]
for name,net,n,output in [('LumaRetouchBlend',blend,512,'blend'),('LumaBlemishDetect',detect,768,'probability'),('LumaBlemishHeal',heal,576,'correction')]:
    rgb=original.resize((n,n),Image.Resampling.BILINEAR)
    x=torch.from_numpy(np.asarray(rgb).astype(np.float32).copy()).permute(2,0,1)[None]/127.5-1
    ml=ct.models.MLModel(str(a.models_dir/(name+'.mlpackage')))
    inputs={'image':rgb}
    with torch.inference_mode():
        if output=='correction':
            keep=np.ones((1,1,n,n),dtype=np.float32);keep[:,:,170:185,190:205]=0;keep[:,:,320:328,360:368]=0.6
            kt=torch.from_numpy(keep)
            expected=((net(x*kt,kt)-x)*(1-kt)*.5).numpy()
            inputs['keep']=keep.astype(np.float16)
        elif output=='probability':expected=torch.sigmoid(net(x)).numpy()
        else:expected=net(x).numpy()
    started=time.perf_counter();actual=ml.predict(inputs)[output].astype(np.float32);elapsed=time.perf_counter()-started
    error=np.abs(actual-expected)
    row={'component':name,'meanAbsoluteError':float(error.mean()),'maxAbsoluteError':float(error.max()),'p99AbsoluteError':float(np.quantile(error,.99)),'predictionSeconds':elapsed,'inputSize':n,'finite':bool(np.isfinite(actual).all())}
    receipt.append(row);print(row,flush=True)
    # Errors measure conversion fidelity only, not aesthetic retouching quality.
    assert row['finite'] and row['meanAbsoluteError']<.002 and row['maxAbsoluteError']<.03
a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(receipt,indent=2))
