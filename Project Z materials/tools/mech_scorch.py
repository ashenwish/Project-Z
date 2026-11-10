"""Обгорание меха: точная таблица цветов PZ-28, alpha и геометрия не меняются.

python tools/mech_scorch.py input.png output.png
"""
import sys

from PIL import Image

MAP = {bytes.fromhex(a):bytes.fromhex(b) for a,b in {
    'e0b84a':'74582a', '9a7a2e':'3e2c1c', '4a3a1c':'211e2c', '74582a':'3e2c1c', '3e2c1c':'15131d',
    'ece8ee':'948ea0', 'c4bfcc':'6b6578', '948ea0':'4a4558', '6b6578':'322e40', '4a4558':'211e2c',
    '322e40':'15131d', '211e2c':'15131d', 'f0cdb4':'a35a5a', 'd49a86':'6e3440', 'a35a5a':'6e3440',
    '6e3440':'3b1f28', '3b1f28':'211e2c', '9fc5c9':'6b6578', '5d8591':'4a4558', '34505c':'322e40',
    '1d2a33':'211e2c', '7fa05a':'4a4558'}.items()}


def scorch(im):
    im=im.convert('RGBA')
    colors={tuple(k):tuple(v) for k,v in MAP.items()}
    out=Image.new('RGBA',im.size)
    out.putdata([colors.get(p[:3],p[:3])+(p[3],) for p in im.getdata()])
    return out


if __name__=='__main__':
    scorch(Image.open(sys.argv[1])).save(sys.argv[2])
