#!/usr/bin/env python3
"""Reproducibly bake sRGB camera-inspired looks without network or imaging dependencies.

Six matrix/tone transforms are adapted from Filmic (MIT, Ying Wang).
Three original upstream CUBEs are copied verbatim; their 17^3 lattice is retained.
Two Xiaomi/Leica-inspired palettes are LumaStudio originals, not vendor profiles.
All existing 30 LUT files remain untouched. --check verifies inputs and outputs.
"""
import argparse
import colorsys
import hashlib
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'Resources/ColorLooks/Filmic'
DEST = ROOT / 'Packages/ColorEngine/Sources/LUTs'
MANIFEST = ROOT / 'Resources/ColorLooks/baked-manifest.json'
PIN = '219e30356cc80ae90e98d78be2af5da149d49116'
# Rows: 3x3 channel matrix plus offsets in 8-bit units, followed by
# contrast, saturation, shadow lift, highlight roll. From Styles.kt.
MATRIX = {
    'hasselbladNatural': (((1.04,.02,0,2),(0,1.02,.01,1),(0,0,.98,-2)),1.05,.96,.02,.04),
    'leicaStandard': (((1.02,0,0,4),(0,1,0,1),(0,0,.96,-3)),1.08,1.02,.01,.05),
    'leicaMonochrom': (((.30,.59,.11,0),(.30,.59,.11,0),(.30,.59,.11,0)),1.18,0,-.02,.03),
    'fujiClassicChrome': (((.98,.04,.02,-4),(.02,.94,.04,-2),(0,.02,.92,4)),1.12,.82,.08,.06),
    'fujiVelvia': (((1.10,-.04,-.02,2),(-.02,1.08,-.04,0),(-.04,-.02,1.06,4)),1.15,1.22,0,.02),
    'fujiAcros': (((.25,.62,.13,0),(.25,.62,.13,0),(.25,.62,.13,0)),1.12,0,.02,.06),
}
CUBES = {'hasselbladXPan':'hasselblad_xpan.cube','leicaChrome':'leica_chrome.cube','fujiAstia':'fuji_astia.cube'}
ORIGINALS = ('xiaomiLeicaClassic','xiaomiLeicaVivid')
ORDER = [*ORIGINALS,'hasselbladNatural','hasselbladXPan','leicaStandard','leicaChrome','leicaMonochrom','fujiClassicChrome','fujiVelvia','fujiAstia','fujiAcros']

def clamp(x):
    return max(0.0, min(1.0, x))

def filmic(rgb, name):
    matrix, contrast, saturation, lift, roll = MATRIX[name]
    channels = [sum(row[i]*rgb[i] for i in range(3))+row[3]/255 for row in matrix]
    # Android ColorMatrix.setSaturation weights and 128/255 contrast pivot.
    y = sum(v*w for v,w in zip(channels,(.213,.715,.072)))
    channels = [clamp((y+(v-y)*saturation-128/255)*contrast+128/255) for v in channels]
    out = []
    for v in channels:
        v = v**(1-lift)
        if roll > 0 and v > .7:
            over = (v-.7)/.3
            v = .7+(.3-roll)*(1-(1-over)**2)
        out.append(clamp(v))
    return out

def smoothstep(a, b, x):
    x = clamp((x-a)/(b-a))
    return x*x*(3-2*x)

def original(rgb, name):
    # Pointwise sRGB grading, never a white-balance/exposure/camera calibration.
    h,s,v = colorsys.rgb_to_hsv(*rgb)
    distance = min(abs(h-.075), 1-abs(h-.075))
    skin = (1-smoothstep(.045,.12,distance))*smoothstep(.08,.25,s)*(1-smoothstep(.7,.95,s))
    y = sum(c*w for c,w in zip(rgb,(.2126,.7152,.0722)))
    if name == 'xiaomiLeicaClassic':
        # Luminance S-curve with a slightly lower midtone; green/blue restraint.
        target = clamp(y+.18*(y-.5)*y*(1-y)-.025*math.sin(math.pi*y))
        sat = .88+.12*skin
        hue = h + .012*math.sin(2*math.pi*h)*(1-skin)
        cast = (.010, .002, -.009)
    else:
        target = clamp(y+.28*(y-.5)*y*(1-y)+.015*math.sin(math.pi*y))
        sat = 1+.20*(1-skin)*(1-.65*s)
        hue = h-.006*math.sin(2*math.pi*h)*(1-skin)
        cast = (.006,.002,-.004)
    changed = colorsys.hsv_to_rgb(hue%1,clamp(s*sat),v)
    changed_y = sum(c*w for c,w in zip(changed,(.2126,.7152,.0722)))
    # Fade chroma smoothly toward gamut boundaries instead of channel clipping.
    chroma = [c-changed_y for c in changed]
    gain = 1.0
    for c in chroma:
        if c>0: gain=min(gain,(1-target)/c)
        if c<0: gain=min(gain,target/-c)
    tint = 4*y*(1-y)
    return [clamp(target+gain*c+cast[i]*tint) for i,c in enumerate(chroma)]

def bake(name):
    if name in CUBES:
        return (SOURCE/CUBES[name]).read_bytes(),17
    dimension = 33
    transform = original if name in ORIGINALS else filmic
    rows = [f'TITLE "LumaStudio Inspired {name}"','LUT_3D_SIZE 33','DOMAIN_MIN 0 0 0','DOMAIN_MAX 1 1 1']
    for b in range(dimension):
        for g in range(dimension):
            for r in range(dimension):
                rows.append(' '.join(f'{v:.7f}' for v in transform((r/32,g/32,b/32),name)))
    return ('\n'.join(rows)+'\n').encode(),dimension

def sha(data):
    return hashlib.sha256(data).hexdigest()

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check',action='store_true')
    args=parser.parse_args()
    upstream=json.loads((SOURCE/'provenance.json').read_text())
    assert upstream['commit']==PIN
    for item in upstream['files']:
        data=(ROOT/item['path']).read_bytes()
        assert len(data)==item['bytes'] and sha(data)==item['sha256'],item['path']
    legacy=json.loads((ROOT/'Resources/ColorLooks/legacy-luts-v0.5.4.json').read_text())
    for name,digest in legacy.items():
        assert sha((DEST/(name+'.cube')).read_bytes())==digest,'Legacy look changed: '+name
    records=[]
    for name in ORDER:
        data,dimension=bake(name)
        destination=DEST/(name+'.cube')
        if args.check:
            assert destination.read_bytes()==data,'Generated LUT differs: '+name
        else:
            destination.write_bytes(data)
        # Independent runtime probes away from lattice nodes, including skin and neutrals.
        probes=[(.11,.34,.63),(.75,.51,.39),(.03,.03,.03),(.18,.18,.18),(.5,.5,.5),(.9,.9,.9),(.97,.97,.97)]
        records.append({'id':name,'path':str(destination.relative_to(ROOT)),'dimension':dimension,'bytes':len(data),'sha256':sha(data),'source':'LumaStudio original' if name in ORIGINALS else 'Filmic MIT '+PIN,'referenceSamples':[{'input':rgb,'output':(original if name in ORIGINALS else filmic)(rgb,name)} for rgb in probes] if name not in CUBES else []})
    manifest={'version':1,'input':'display-referred sRGB 0..1 after RAW development; not Log or linear sensor RGB','output':'sRGB 0..1, SDR creative look','scope':'Independent brand-inspired approximations, no camera-pair calibration or manufacturer endorsement. Filmic adaptation uses floating-point tone curves, omits 8-bit intermediate rounding, grain and crop. Original 17^3 cubes unchanged.','legacyCount':30,'looks':records}
    encoded=(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n').encode()
    if args.check:
        assert MANIFEST.read_bytes()==encoded,'Manifest differs'
    else:
        MANIFEST.write_bytes(encoded)
    print(f'Verified {len(ORDER)} camera-inspired looks and {len(legacy)} unchanged legacy LUTs.' if args.check else f'Baked {len(ORDER)} camera-inspired looks; 30 legacy LUTs unchanged.')

if __name__=='__main__':
    main()
