"""Этап 3: Aseprite, метаданные атак, эффекты, контрольные листы и превью.

python tools/mech_attack_sheets.py [папка art/mech]
Использует те же проверки и сборку, что этап 2. Godot не изменяется.
"""
import json
import math
from pathlib import Path
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mech_damage_sheets import ROOT, RD, OUT, DIRS, build
import fx_gen


def index_at(ms, durations):
    elapsed = 0
    for i, duration in enumerate(durations):
        elapsed += duration
        if ms < elapsed:
            return i
    return len(durations)-1


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    attacks = {}
    count = 0
    for anim in ['shoot', 'stomp']:
        m = json.loads((RD/f'mech_{anim}.json').read_text(encoding='utf-8'))
        rows = [{'tag': anim+'_'+d, 'files': [str(RD/f'mech_scout_{anim}_{d}_{i}.png') for i in range(m['frames'])]} for d in DIRS]
        atlas = build('mech_scout_'+anim, rows, m['durations_ms'], (256,256))
        for d in DIRS:
            idle = np.array(Image.open(ROOT/f'art/mech/render/mech_scout_idle_{d}_0.png'))
            rest = np.array(Image.open(RD/f'mech_scout_{anim}_{d}_{m["frames"]-1}.png'))
            assert np.array_equal(idle, rest), (anim,d,'return to idle')
        for tracks in m['anchors'].values():
            assert set(tracks) == set(DIRS)
            assert all(len(ps)==m['frames'] and all(0<=x<256 and 0<=y<256 for x,y in ps) for ps in tracks.values())
        for indices in m['events'].values():
            assert all(0<=i<m['frames'] for i in indices)
        if anim == 'shoot':
            assert m['events']['fire']==[0,2] and sum(m['durations_ms'])==200
            for M in m['foot_r_matrix_px']:
                assert np.allclose(M,np.eye(4),atol=1e-5), 'Shooting feet move'
        else:
            assert m['events']['impact']==[3]
            assert abs(m['foot_r_matrix_px'][3][2][3])<0.01, 'Stomp misses floor'
            assert abs(m['foot_r_matrix_px'][3][1][3]-30)<0.01, 'Stomp reach'
            assert abs(m['foot_r_matrix_px'][2][2][3]-26)<0.01, 'Missing foot lift'
        (OUT/f'mech_{anim}.json').write_text(json.dumps(m,ensure_ascii=False,indent=2),encoding='utf-8')
        contact = Image.new('RGB',(256*m['frames'],280*8),'#211e2c')
        draw = ImageDraw.Draw(contact)
        for row,d in enumerate(DIRS):
            for i in range(m['frames']):
                im=atlas.crop((i*256,row*256,(i+1)*256,(row+1)*256))
                contact.paste(im,(i*256,row*280+24),im)
                draw.text((i*256+8,row*280+6),d+' / '+anim+' / '+str(i),fill='white')
        contact.save(OUT/f'mech_{anim}_contact.png')
        attacks[anim]=m
        count += m['frames']*8

    effects = {}
    for name,(rows,size,durs) in fx_gen.maxim_effects().items():
        jobs=[]
        for r,row in enumerate(rows):
            files=[]
            for i,im in enumerate(row):
                path=RD/f'{name}_{r}_{i}.png';im.save(path);files.append(str(path))
            jobs.append({'tag': DIRS[r] if len(rows)==8 else name, 'files': files})
        build(name,jobs,durs,size,OUT.parent/'fx')
        effects[name]={'sheet':'../fx/'+name+'.png','canvas':list(size),'frames':len(durs),
                       'rows':len(rows),'durations_ms':durs,'pivot':[size[0]//2,22 if name=='stomp_dust' else size[1]//2]}
        count += len(rows)*len(durs)

    # В превью эффекты скрываются за корпусом по глубине служебного прохода.
    depth_cache={}
    def overlay(canvas,fx,xy,world,anim,d,i):
        key=(anim,d,i)
        a=math.radians(DIRS.index(d)*45)
        forward=np.array([-math.cos(math.pi/6)*math.sin(a),-math.cos(math.pi/6)*math.cos(a),-0.5])
        if key not in depth_cache:
            with np.load(RD/f'passes_{anim}_{d}_{i}.npz') as p:
                depth=((p['pos'][...,:3]-.5)/.05*56)@forward
                depth_cache[key]=(depth,p['id'][...,3]>.5)
        depth,hit=depth_cache[key]
        layer=Image.new('RGBA',(256,256));layer.paste(fx,(round(xy[0]),round(xy[1])))
        arr=np.array(layer)
        arr[(hit)&(depth<np.array(world)@forward-.5),3]=0
        canvas.alpha_composite(Image.fromarray(arr))

    for anim in attacks:
        m=attacks[anim];frames=[]
        for tick in range(60):
            ms=tick*20
            strip=Image.new('RGB',(256*4,280),'#211e2c');draw=ImageDraw.Draw(strip)
            for col,d in enumerate(['se','s','e','nw']):
                t=ms%200 if anim=='shoot' and ms<600 else ms if anim=='stomp' else 200
                i=index_at(t,m['durations_ms'])
                im=Image.open(RD/f'mech_scout_{anim}_{d}_{i}.png').convert('RGBA')
                a=math.radians(DIRS.index(d)*45)
                if anim=='shoot':
                    age=ms%100
                    if ms<600:
                        if age<60:
                            f=0 if age<25 else 1
                            effect=Image.open(RD/f'flash_maxim_{DIRS.index(d)}_{f}.png')
                            p=m['anchors']['muzzle'][d][i]
                            world=np.array(m['anchors_frames_m']['muzzle'][i])*56
                            overlay(im,effect,(p[0]-16,p[1]-16),world,anim,d,i)
                        if 15<=age<80:
                            dist=15+age*.45
                            effect=Image.open(RD/f'tracer_maxim_{DIRS.index(d)}_0.png')
                            source=0 if ms%200<100 else 2
                            p=m['anchors']['muzzle'][d][source]
                            world=np.array(m['anchors_frames_m']['muzzle'][source])*56+[0,dist,0]
                            overlay(im,effect,(p[0]+math.sin(a)*dist-16,p[1]+.5*math.cos(a)*dist-16),world,anim,d,i)
                    for shot in range(0,600,100):
                        age=ms-shot
                        if 0<=age<450:
                            sec=age/1000
                            source=0 if shot%200==0 else 2
                            p=m['anchors']['eject'][d][source]
                            effect=Image.open(RD/f'shell_maxim_0_{int(age/50)%8}.png')
                            dx,dz=50*sec,60*sec-160*sec*sec
                            world=np.array(m['anchors_frames_m']['eject'][source])*56+[-dx,0,dz]
                            overlay(im,effect,(p[0]+math.cos(a)*dx-6,p[1]-.5*math.sin(a)*dx-math.cos(math.pi/6)*dz-6),world,anim,d,i)
                else:
                    age=ms-sum(m['durations_ms'][:3])
                    if 0<=age<320:
                        f=index_at(age,effects['stomp_dust']['durations_ms'])
                        effect=Image.open(RD/f'stomp_dust_0_{f}.png')
                        p=m['anchors']['foot_r'][d][3]
                        world=np.array(m['anchors_frames_m']['foot_r'][3])*56
                        overlay(im,effect,(p[0]-32,p[1]-22),world,anim,d,i)
                strip.paste(im,(col*256,24),im)
                draw.text((col*256+8,5),d+' / '+anim,fill='white')
            frames.append(strip)
        frames[0].save(OUT/f'mech_{anim}_preview.gif',save_all=True,append_images=frames[1:],duration=20,loop=0,optimize=False)
    contract={'schema_version':1,'directions':DIRS,'attacks':{name:{'sheet':f'mech_scout_{name}.png','metadata':f'mech_{name}.json',
              'frames':m['frames'],'durations_ms':m['durations_ms'],'events':m['events'],'loop':m['loop'],'canvas':[256,256],'pivot':[128,218]}
              for name,m in attacks.items()},'effects':effects,'integration':'Asset stage 3; gameplay, damage and sound are stage 5.'}
    (OUT/'mech_attacks.json').write_text(json.dumps(contract,indent=2),encoding='utf-8')
    report={'status':'PASS','frames':count,'body_frames':80,'checks':['PZ palette','binary alpha','no clipping','Aseprite pixels/timing/tags',
            '16 exact returns to idle','attack events','seven anchor tracks','stomp floor contact'],
            'not_tested':['Godot gameplay','audio']}
    (OUT/'mech_attacks_qa.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps(report))


if __name__=='__main__':
    main()
