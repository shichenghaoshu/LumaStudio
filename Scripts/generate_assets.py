#!/usr/bin/env python3
"""Render the original aperture icon into Apple app icon slots; dev-only."""
from pathlib import Path
import subprocess,json
root=Path(__file__).resolve().parents[1]
catalog=root/'Resources/Assets.xcassets';app=catalog/'AppIcon.appiconset';app.mkdir(parents=True,exist_ok=True)
(catalog/'Contents.json').write_text(json.dumps({'info':{'author':'xcode','version':1}}))
images=[]
def render(idiom,size,scale,name):
    n=round(float(size)*scale)
    subprocess.run(['sips','-z',str(n),str(n),str(root/'Resources/Icons/LumaStudio-1024.png'),'--out',str(app/name)],stdout=subprocess.DEVNULL,check=True)
    images.append({'idiom':idiom,'size':f'{size}x{size}','scale':f'{scale}x','filename':name})
for size in [16,32,128,256,512]:
    for scale in [1,2]: render('mac',size,scale,f'mac-{size}-{scale}.png')
for size,scales in [(20,[1,2]),(29,[1,2]),(40,[1,2]),(76,[1,2]),(83.5,[2])]:
    for scale in scales: render('ipad',size,scale,f'pad-{size}-{scale}.png')
render('ios-marketing',1024,1,'ios-1024.png')
(app/'Contents.json').write_text(json.dumps({'images':images,'info':{'author':'xcode','version':1}},indent=2))
