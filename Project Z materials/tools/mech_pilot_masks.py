"""Depth-tested pilot hit masks, using the same rays and geometry as approved art."""
from pathlib import Path
import sys,json,os
import numpy as np
from PIL import Image

def build(root: Path, out: Path):
    os.environ['PZ_MATERIALS_ROOT']=str(root)
    os.environ['PZ_MECH_RENDER_DIR']=str(root/'art/mech/render')
    sys.path.insert(0,str(root/'tools'))
    import mech_render as mr
    hr=mr.hr
    hr.W,hr.H,hr.PIVOT=256,256,(128,218)
    for anim in ['idle','walk','hit','shoot','stomp']:
        m=json.loads((out/f'{anim}.json').read_text());sheet=Image.new('L',(256*m['frames'],2048))
        for row,d in enumerate(['s','se','e','ne','n','nw','w','sw']):
            for i in range(m['frames']):
                b=mr.pilot_layers(m['body_dz_px'][i] if 'body_matrix_px' not in m else 0)
                if 'body_matrix_px' in m:
                    M=np.array(m['body_matrix_px'][i]);b=mr.er.rotate_bones(b,M[:3,:3],(0,0,0),M[:3,3])
                pr,ps,pf,pp,pt=hr.render(hr.DIRS[d],b)
                P=np.load(root/f'art/mech/render/passes_{anim}_{d}_{i}.npz')
                p=(P['pos'][...,:3]-.5)/.05/mr.S
                _,_,fb=mr.light(d)
                tt=np.where(P['id'][...,3]>.5,hr.RAY_NEAR+p@fb,np.inf)
                mask=(pp>=0)&(pt<tt)
                sheet.paste(Image.fromarray(mask.astype('uint8')*255),(i*256,row*256))
            print('pilot mask',anim,d,flush=True)
        sheet.save(out/f'{anim}_pilot.png')
