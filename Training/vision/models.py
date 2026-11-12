import torch
from torch import nn

class Block(nn.Sequential):
    def __init__(self, source, target):
        super().__init__(nn.Conv2d(source,target,3,padding=1),nn.GroupNorm(8,target),nn.SiLU(),
                         nn.Conv2d(target,target,3,padding=1),nn.GroupNorm(8,target),nn.SiLU())

class SegmentationUNet(nn.Module):
    """Independent specialist model; base64 FP16 parameters start in the 10-50 MB experiment budget."""
    def __init__(self, channels=4, base=64):
        super().__init__()
        self.first=Block(3,base);self.second=Block(base,base*2);self.third=Block(base*2,base*4)
        self.bottom=Block(base*4,base*8);self.up3=Block(base*12,base*4);self.up2=Block(base*6,base*2);self.up1=Block(base*3,base)
        self.output=nn.Conv2d(base,channels,1)
    def forward(self, image):
        a=self.first(image);b=self.second(torch.nn.functional.avg_pool2d(a,2));c=self.third(torch.nn.functional.avg_pool2d(b,2))
        d=self.bottom(torch.nn.functional.avg_pool2d(c,2))
        d=self.up3(torch.cat([torch.nn.functional.interpolate(d,size=c.shape[-2:],mode="bilinear",align_corners=False),c],1))
        d=self.up2(torch.cat([torch.nn.functional.interpolate(d,size=b.shape[-2:],mode="bilinear",align_corners=False),b],1))
        d=self.up1(torch.cat([torch.nn.functional.interpolate(d,size=a.shape[-2:],mode="bilinear",align_corners=False),a],1))
        return self.output(d)

class ProbabilityOutput(nn.Module):
    def __init__(self, network):super().__init__();self.network=network
    def forward(self,image):return torch.sigmoid(self.network(image))
