"""Build the Godot mech asset package from approved source renders (no Blender render)."""
from pathlib import Path
import json, shutil, subprocess, argparse
import numpy as np
from PIL import Image, ImageFilter
from scipy import signal

ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT.parent/'project Z/z'
OUT = GAME/'assets/mech'
DIRS = ['s','se','e','ne','n','nw','w','sw']

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    src=ROOT/'art/mech'; rd=src/'render'
    lut=json.loads((src/'mech_scorch.json').read_text())
    for anim in ['idle','walk','hit','shoot','stomp','die','die_decap','shatter','wreck']:
        m=json.loads(((src if (src/f'mech_{anim}.json').exists() else rd)/f'mech_{anim}.json').read_text())
        name=('mech_' if anim in ['shatter','wreck'] else 'mech_scout_')+anim
        png=src/f'{name}.png'
        if png.exists(): sheet=Image.open(png).convert('RGBA')
        else:
            sheet=Image.new('RGBA',(256*m['frames'],256*8))
            for row,d in enumerate(DIRS):
                for i in range(m['frames']):sheet.paste(Image.open(rd/f'mech_scout_{anim}_{d}_{i}.png'),(i*256,row*256))
        sheet.save(OUT/f'{anim}.png')
        a=np.asarray(sheet).copy(); b=a.copy()
        for old,new in lut.items():
            rgb=tuple(bytes.fromhex(old)); mask=np.all(a[:,:,:3]==rgb,axis=2)
            b[mask,:3]=tuple(bytes.fromhex(new))
        if anim not in ['shatter','wreck']: Image.fromarray(b).save(OUT/f'{anim}_charred.png')
        (OUT/f'{anim}.json').write_text(json.dumps(m,indent=2))
        # The RGB channels identify the three detachable pieces. Zero elsewhere.
        mask_sheet=Image.new('RGB',sheet.size)
        for row,d in enumerate(DIRS):
            for i in range(m['frames']):
                geom='die' if anim=='die_decap' else anim
                ids=np.rint(np.load(rd/f'passes_{geom}_{d}_{i}.npz')['id'][:,:,0]).astype(int)
                channels=[]
                for obj in [30,18,47]:
                    mask=Image.fromarray(np.uint8(ids==obj)*255)
                    # Include the 1px ink silhouette, but never erase adjacent geometry.
                    expanded=np.asarray(mask.filter(ImageFilter.MaxFilter(3)))>0
                    channels.append(np.uint8((ids==obj)|((ids==0)&expanded))*255)
                mask_sheet.paste(Image.fromarray(np.stack(channels,axis=2)),(i*256,row*256))
        mask_sheet.save(OUT/f'{anim}_parts.png')
    for name in ['mech_piece_cover','mech_piece_shield','mech_piece_cap','mech_pilot_head']:
        shutil.copy2(src/f'{name}.png',OUT/f'{name}.png')
    for name in ['mech_damage','mech_attacks','mech_death','mech_pilot_head']:
        shutil.copy2(src/f'{name}.json',OUT/f'{name}.json')
    for name in ['sparks_metal','flash_maxim','tracer_maxim','shell_maxim','stomp_dust','smoke_mech','blast_mech','flame_mech','pilot_blood']:
        shutil.copy2(ROOT/f'art/fx/{name}.png',OUT/f'{name}.png')
    from mech_pilot_masks import build
    build(ROOT, OUT)
    audio(GAME/'assets/audio')
    print('Mech package built:',len(list(OUT.iterdir())),'files')

def audio(out):
    """CC0 source layers already shipped with the game + seeded procedural layers."""
    ff=shutil.which('ffmpeg'); sr=44100; rng=np.random.default_rng(18)
    meta=json.loads((out/'sfx.json').read_text())
    def source(group,seconds,pitch=1):
        raw=subprocess.check_output([ff,'-v','error','-i',str(out/meta[group][0]),'-f','f32le','-ac','1','-ar',str(sr),'-'])
        a=np.frombuffer(raw,np.float32).copy()
        a=np.interp(np.arange(int(len(a)/pitch))*pitch,np.arange(len(a)),a)
        return np.pad(a,(0,max(0,int(sr*seconds)-len(a))))[:int(sr*seconds)]
    def noise(seconds,cut):
        a=rng.normal(size=int(sr*seconds)); sos=signal.butter(3,cut,fs=sr,output='sos'); return signal.sosfilt(sos,a)
    def write(name,a):
        a=np.asarray(a,float); a-=a.mean(); a[:220]*=np.linspace(0,1,220); a[-220:]*=np.linspace(1,0,220)
        a=a/max(np.max(np.abs(a)),.01)*.82
        subprocess.run([ff,'-v','error','-y','-f','f32le','-ar',str(sr),'-ac','1','-i','-','-c:a','libvorbis','-q:a','5',str(out/f'{name}.ogg')],input=a.astype(np.float32).tobytes(),check=True)
        meta[name]=[f'{name}.ogg']
    t=np.arange(int(sr*.19))/sr
    write('mech_maxim',source('revolver',.19,.85)*.7+source('clang',.19,1.4)*.23+noise(.19,4500)*np.exp(-t*45)*.45)
    t=np.arange(int(sr*.65))/sr
    step=source('clang',.65,.55)*.55+source('land',.65,.65)*.55+np.sin(2*np.pi*53*t)*np.exp(-t*18)*.28
    write('mech_step',step)
    write('mech_stomp',step+source('slam',.65,.7)*.6)
    write('mech_metal_hit',source('clang',.48,.8)*.8+source('hit',.48,1.2)*.22)
    t=np.arange(int(sr*1.6))/sr
    write('mech_explosion',source('slam',1.6,.6)*.65+source('fire_burst',1.6,.7)*.5+noise(1.6,3500)*np.exp(-t*4)*.8+np.sin(2*np.pi*(65*t-12*t*t))*np.exp(-t*5)*.55)
    write('mech_steam',source('steam_puff',.75,.75))
    (out/'sfx.json').write_text(json.dumps(meta,indent=1))
    (out/'MECH_CREDITS.md').write_text('Mech sounds: derived from the existing CC0 sources listed in CREDITS.md / source audio credits.\nLayers: revolver + clang (Maxim); clang + land (steps); clang + hit (armor); slam + fire_burst (explosion); steam_puff (steam).\nAdditional thumps and filtered noise generated procedurally with seed 18. No human voices.\n',encoding='utf-8')

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--materials',type=Path,default=ROOT)
    parser.add_argument('--game',type=Path)
    args=parser.parse_args()
    ROOT=args.materials.resolve()
    GAME=(args.game or ROOT.parent/'project Z/z').resolve()
    OUT=GAME/'assets/mech'
    main()
