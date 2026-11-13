#!/usr/bin/env python3
"""Generate 24 original LumaStudio looks. No third-party filter data is used."""
from pathlib import Path
import math

ROOT=Path(__file__).resolve().parents[1]/'Packages/ColorEngine/Sources/LUTs'
# contrast, saturation, RGB cast, lifted black, monochrome blend
LOOKS={
 'ivory':(.96,.86,(.025,.015,-.005),.018,0),
 'rose':(.97,.94,(.035,-.012,.016),.012,0),
 'peach':(.98,.90,(.045,.006,-.016),.016,0),
 'softPortrait':(.91,.90,(.018,.006,-.004),.025,0),
 'amber':(1.08,.92,(.055,.020,-.035),.01,0),
 'golden':(1.03,1.03,(.065,.028,-.040),.015,0),
 'copper':(1.14,.83,(.055,-.004,-.040),.02,0),
 'sunset':(1.07,1.08,(.070,-.002,-.035),.025,0),
 'silver':(1.08,1,(-.008,.002,.018),.012,1),
 'mono':(1.04,1,(0,0,0),0,1),
 'matteMono':(.94,1,(.008,.006,.004),.065,1),
 'noir':(1.27,1,(0,0,.006),.005,1),
 'forest':(1.08,.94,(-.022,.020,-.018),.018,0),
 'jade':(.99,.87,(-.022,.024,.011),.035,0),
 'ocean':(1.05,1.04,(-.027,.014,.043),.008,0),
 'alpine':(1.11,.92,(-.012,.012,.025),0,0),
 'faded':(.90,.78,(.018,.010,.018),.075,0),
 'vintage':(1.03,.72,(.043,.016,-.021),.048,0),
 'instant':(.95,.88,(.028,.014,.007),.055,0),
 'cinema':(1.16,.83,(.020,.008,-.015),.02,0),
 'tealOrange':(1.13,.90,(.015,.012,-.006),.025,0),
 'night':(1.17,.75,(-.025,-.006,.045),.018,0),
 'pastel':(.88,.75,(.030,.014,.025),.04,0),
 'airy':(.90,.85,(.022,.024,.015),.035,0),
}
def clamp(x):return min(1,max(0,x))
def transform(rgb,name):
 contrast,saturation,cast,lift,mono=LOOKS[name]
 y=sum(v*w for v,w in zip(rgb,(.2126,.7152,.0722)))
 channels=[y+(v-y)*saturation*(1-mono) for v in rgb]
 out=[]
 for i,v in enumerate(channels):
  v=(v-.5)*contrast+.5
  if name in ('cinema','tealOrange'):
   v+=(((-.024,.018,.032)[i]*(1-y))+((.038,.009,-.024)[i]*y))*(1.6 if name=='tealOrange' else .6)
  out.append(clamp(lift+v*(1-lift)+cast[i]*(.45+.55*(1-abs(y-.5)*2))))
 return out
def main():
 ROOT.mkdir(parents=True,exist_ok=True)
 for name in LOOKS:
  lines=[f'TITLE "LumaStudio Original {name}"','LUT_3D_SIZE 17','DOMAIN_MIN 0 0 0','DOMAIN_MAX 1 1 1']
  for b in range(17):
   for g in range(17):
    for r in range(17):lines.append(' '.join(f'{v:.6f}' for v in transform((r/16,g/16,b/16),name)))
  (ROOT/(name+'.cube')).write_text('\n'.join(lines)+'\n')
 print(f'Generated {len(LOOKS)} original LUTs; the original six remain unchanged.')
if __name__=='__main__':main()
