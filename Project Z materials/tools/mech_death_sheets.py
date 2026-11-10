"""Этап 4: смерть пилота, распад, остов, обгорание и эффекты. Godot не изменяется."""
import json
import math
from pathlib import Path
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0,str(Path(__file__).resolve().parent))
from mech_damage_sheets import ROOT, RD, OUT, DIRS, build
from mech_scorch import scorch, MAP
import fx_gen


def at(ms,durations):
    total=0
    for i,d in enumerate(durations):
        total+=d
        if ms<total:return i
    return len(durations)-1


def screen(point,d):
    x,y,z=point;a=math.radians(DIRS.index(d)*45)
    return (159.5-math.cos(a)*x+math.sin(a)*y,
            297.5+.5*(math.sin(a)*x+math.cos(a)*y)-math.sqrt(3)/2*z)


def contact(name,rows,w=256,h=256):
    out=Image.new('RGB',(w*len(rows[0]['files']),(h+24)*len(rows)),'#211e2c');draw=ImageDraw.Draw(out)
    for y,row in enumerate(rows):
        for x,path in enumerate(row['files']):
            im=Image.open(path);out.paste(im,(x*w,y*(h+24)+24),im)
            draw.text((x*w+6,y*(h+24)+5),row['tag']+' / '+str(x),fill='white')
    out.save(OUT/(name+'_contact.png'))


def main():
    OUT.mkdir(parents=True,exist_ok=True);count=0;meta={}
    for anim in ['die','die_decap','shatter','wreck']:
        m=json.loads((RD/f'mech_{anim}.json').read_text(encoding='utf-8'))
        if anim=='die_decap':m['events']['head_detached']=[0]
        rows=[]
        for d in DIRS:
            paths=[]
            for i in range(m['frames']):
                src=RD/f'mech_scout_{anim}_{d}_{i}.png'
                if anim in ['shatter','wreck']:
                    dst=RD/f'mech_{anim}_{d}_{i}.png';scorch(Image.open(src)).save(dst)
                else:dst=src
                paths.append(str(dst))
            rows.append({'tag':anim+'_'+d,'files':paths})
        name='mech_'+anim if anim in ['shatter','wreck'] else 'mech_scout_'+anim
        build(name,rows,m['durations_ms'],(256,256));contact(name,rows)
        if anim.startswith('die'):
            assert m['events']['explode']==[5]
            assert sum(m['durations_ms'][:5])==900
            assert all(v[-1]==0 for v in m['visible_pilot_pixels'].values()),'Pilot persists after explosion'
            for d in ['s','se','e','sw']:
                assert m['visible_pilot_pixels'][d][0]>0 and m['visible_pilot_pixels'][d][4]>0,(anim,d,'missing pilot')
        if anim=='wreck':
            assert m['pilot'] is False and m['pivot']==[128,128] and m['floor_basis']['scale_y']==2
        if anim=='shatter':assert m['pilot'] is False and m['pivot']==[128,200]
        (OUT/f'mech_{anim}.json').write_text(json.dumps(m,indent=2),encoding='utf-8');meta[anim]=m;count+=m['frames']*8
    head=json.loads((RD/'mech_pilot_head.json').read_text())
    build('mech_pilot_head',[{'tag':'tumble','files':[str(RD/f'mech_pilot_head_s_{i}.png') for i in range(8)]}],head['durations_ms'],(64,64))
    (OUT/'mech_pilot_head.json').write_text(json.dumps(head,indent=2),encoding='utf-8');count+=8
    burn={}
    for anim in ['idle','walk']:
        m=json.loads((ROOT/f'art/mech/render/mech_{anim}.json').read_text())
        rows=[]
        for d in DIRS:
            paths=[]
            for i in range(m['frames']):
                original=Image.open(ROOT/f'art/mech/render/mech_scout_{anim}_{d}_{i}.png').convert('RGBA')
                charred=scorch(original)
                assert charred.getchannel('A').tobytes()==original.getchannel('A').tobytes(),'Scorch changes alpha'
                path=RD/f'mech_scout_{anim}_charred_{d}_{i}.png';charred.save(path);paths.append(str(path))
            rows.append({'tag':anim+'_'+d,'files':paths})
        build('mech_scout_'+anim+'_charred',rows,m['durations_ms'],(256,256));burn[anim]=m;count+=m['frames']*8
    palette=[bytes.fromhex(h) for h in (ROOT/'art/palette/pz-28.hex').read_text().split()]
    lut=Image.new('RGBA',(len(palette),2))
    lut.putdata([tuple(v)+(255,) for v in palette]+[tuple(MAP.get(v,v))+(255,) for v in palette])
    lut.save(OUT/'mech_scorch_lut.png')
    table={v.hex():MAP.get(v,v).hex() for v in palette}
    assert set(table.values())<=set(table),'Scorch leaves PZ palette'
    (OUT/'mech_scorch.json').write_text(json.dumps(table,indent=2),encoding='utf-8')
    texture=OUT/'textures';texture.mkdir(exist_ok=True)
    scorch(Image.open(ROOT/'art/mech/textures/mech_scout_pz.png')).save(texture/'mech_scout_charred.png')
    effects={}
    for name,(rows,size,durs) in fx_gen.mech_death_effects().items():
        jobs=[]
        for r,row in enumerate(rows):
            paths=[]
            for i,im in enumerate(row):
                path=RD/f'{name}_{r}_{i}.png';im.save(path);paths.append(str(path))
            jobs.append({'tag':name,'files':paths})
        build(name,jobs,durs,size,OUT.parent/'fx')
        effects[name]={'sheet':'../fx/'+name+'.png','canvas':list(size),'frames':len(durs),'durations_ms':durs,
                       'pivot':[32,86] if name in ['smoke_mech','flame_mech'] else [64,68] if name=='blast_mech' else [32,32]}
        count+=len(durs)

    depth_cache={}
    def composite(cell,im,xy,point,d,context=None):
        layer=Image.new('RGBA',cell.size);layer.alpha_composite(im,(round(xy[0]),round(xy[1])))
        if context is not None:
            geom,i,pivot=context;key=(geom,d,i)
            a=math.radians(DIRS.index(d)*45);forward=np.array([-math.sqrt(3)/2*math.sin(a),-math.sqrt(3)/2*math.cos(a),-.5])
            if key not in depth_cache:
                with np.load(RD/f'passes_{geom}_{d}_{i}.npz') as p:
                    depth_cache[key]=(((p['pos'][...,:3]-.5)/.05*56)@forward,p['id'][...,3]>.5)
            depth,hit=depth_cache[key];arr=np.array(layer)
            x,y=160-pivot[0],298-pivot[1];h=min(256,cell.height-y);w=min(256,cell.width-x)
            blocked=hit[:h,:w]&(depth[:h,:w]<np.array(point)@forward-.5)
            patch=arr[y:y+h,x:x+w,3];patch[blocked]=0
            layer=Image.fromarray(arr)
        cell.alpha_composite(layer)

    def effect(cell,name,ms,point,d,context=None):
        e=effects[name]
        if ms<0 or ms>=sum(e['durations_ms']):return
        i=at(ms,e['durations_ms']);im=Image.open(RD/f'{name}_0_{i}.png')
        x,y=screen(point,d);composite(cell,im,(x-e['pivot'][0],y-e['pivot'][1]),point,d,context)

    def place(cell,path,pivot):
        im=Image.open(path);cell.alpha_composite(im,(160-pivot[0],298-pivot[1]))

    # Превью: кровь и смерть -> наклон/дым -> взрыв/распад -> неподвижный остов на полу.
    for variant in ['die','die_decap']:
        m=meta[variant];frames=[]
        for tick in range(75):
            ms=tick*40;out=Image.new('RGB',(1280,360),'#211e2c');draw=ImageDraw.Draw(out)
            for col,d in enumerate(['se','s','e','nw']):
                cell=Image.new('RGBA',(320,360),(33,30,44,255))
                if ms<1060:
                    i=at(ms,m['durations_ms']);place(cell,RD/f'mech_scout_{variant}_{d}_{i}.png',m['pivot'])
                    context=('die',i,m['pivot'])
                elif ms<1240:
                    i=at(ms-1060,meta['shatter']['durations_ms']);place(cell,RD/f'mech_shatter_{d}_{i}.png',meta['shatter']['pivot'])
                    context=('shatter',i,meta['shatter']['pivot'])
                else:
                    place(cell,RD/f'mech_wreck_{d}_0.png',meta['wreck']['pivot']);context=('wreck',0,meta['wreck']['pivot'])
                point=m['anchors_frames_m']['pilot_hit'][0]
                effect(cell,'pilot_blood',ms,np.array(point)*56,d,context)
                if variant=='die_decap':
                    t=min(ms/1000,.88);p=np.array(head['source_center_px'])+[-25*t,25*t,35*t-250*t*t]
                    p[2]=max(p[2],3)
                    i=int(ms/70)%8 if p[2]>3 else 5
                    x,y=screen(p,d);piece=Image.open(RD/f'mech_pilot_head_s_{i}.png');composite(cell,piece,(x-32,y-32),p,d,context)
                for emission in range(240,900,160):
                    i=at(emission,m['durations_ms']);p=np.array(m['anchors_frames_m']['steam_r'][i])*56
                    effect(cell,'smoke_mech',ms-emission,p,d)
                blast=np.array(m['anchors_frames_m']['body'][5])*56
                effect(cell,'blast_mech',ms-900,blast,d)
                if ms>=1240:
                    for emission in range(1240,3000,240):effect(cell,'smoke_mech',ms-emission,[0,0,20],d)
                out.paste(cell,(col*320,0));draw.text((col*320+8,8),d+' / '+variant,fill='white')
            frames.append(out)
        frames[0].save(OUT/f'mech_{variant}_preview.gif',save_all=True,append_images=frames[1:],duration=40,loop=0,optimize=False)
    frames=[]
    for tick in range(50):
        ms=tick*40;out=Image.new('RGB',(1280,360),'#211e2c');draw=ImageDraw.Draw(out)
        for col,d in enumerate(['se','s','e','nw']):
            cell=Image.new('RGBA',(320,360),(33,30,44,255));m=burn['walk'];i=at(ms%1000,m['durations_ms'])
            place(cell,RD/f'mech_scout_walk_charred_{d}_{i}.png',[128,218])
            p=np.array(m['anchors_m']['body'])*56+[0,0,m['body_dz_px'][i]]
            effect(cell,'flame_mech',ms%640,p,d)
            for emission in range(0,2000,240):effect(cell,'smoke_mech',ms-emission,p+[0,0,25],d)
            out.paste(cell,(col*320,0));draw.text((col*320+8,8),d+' / burning',fill='white')
        frames.append(out)
    frames[0].save(OUT/'mech_burning_preview.gif',save_all=True,append_images=frames[1:],duration=40,loop=0,optimize=False)
    contract={'schema_version':1,'directions':DIRS,'death':{a:{'sheet':('mech_scout_'+a if a.startswith('die') else 'mech_'+a)+'.png',
              'metadata':'mech_'+a+'.json','frames':m['frames'],'durations_ms':m['durations_ms'],'pivot':m['pivot'],'events':m.get('events',{})} for a,m in meta.items()},
              'sequence':['die or die_decap','shatter','wreck'],'floor_basis':meta['wreck']['floor_basis'],
              'burning':{'idle':'mech_scout_idle_charred.png','walk':'mech_scout_walk_charred.png','palette_map':'mech_scorch.json','lut':'mech_scorch_lut.png'},
              'effects':effects,'head':'mech_pilot_head.png','integration':'Asset stage 4. Physics, explosion damage, AI and audio are stage 5.'}
    (OUT/'mech_death.json').write_text(json.dumps(contract,indent=2),encoding='utf-8')
    report={'status':'PASS','frames':count,'aseprite_files':11,'checks':['PZ palette','binary alpha','no clipping','11 Aseprite roundtrips',
            'pilot visibility and removal','death event 900 ms','floor basis','burning preserves alpha','scorch LUT stays in palette'],
            'not_tested':['Godot gameplay','explosion damage','audio']}
    (OUT/'mech_death_qa.json').write_text(json.dumps(report,indent=2),encoding='utf-8');print(json.dumps(report))


if __name__=='__main__':main()
