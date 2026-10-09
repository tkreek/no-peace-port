#!/usr/bin/env python3
"""Debug: composite an .alf map's terrain (atlas + ground textures) to PNG.

Usage: compose_terrain.py <map.alf> <steppe|wiese> <x> <y> <width> <height> <out.png>
Reads the biome from original/extracted/america0 (see tools/extract_rda.js).
"""
import sys,struct,subprocess,os
HERE=os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0,HERE)
from rd_chunks import read_chunks
from rd_sprites import read_pic_indexed
mp,biome,ox,oy,W,H,out=sys.argv[1],sys.argv[2],*map(int,sys.argv[3:7]),sys.argv[7]
L=os.path.join(HERE,f'../../original/extracted/america0/{biome}/gfx/landschaft/')
C=dict(read_chunks(mp)); cols,rows=struct.unpack_from('<II',C['LVL_INFO'],0x114)
cells=struct.unpack_from(f'<{cols*rows}I',C['LVMATRIX'])
aw,ah,apal,atlas=read_pic_indexed(L+'steppe.pic')
tex={}
for i in range(1,64):
  p=L+f'steppe{i}.pic'
  if os.path.exists(p): tex[i]=read_pic_indexed(p)
rgb=bytearray(W*H*3)
for y in range(H):
  wy=oy+y
  for x in range(W):
    wx=ox+x
    cell=cells[(wy//32)*cols+wx//32]&0xffff
    idx=atlas[((cell//20)*32+wy%32)*aw+(cell%20)*32+wx%32]
    t=tex.get(idx)
    if t:
      tw,th,tp,tpx=t; k=tpx[(wy%th)*tw+wx%tw]; c=tp[k*3:k*3+3]
    else: c=apal[idx*3:idx*3+3]
    rgb[(y*W+x)*3:(y*W+x)*3+3]=c
subprocess.run(['magick','ppm:-',out],input=f'P6\n{W} {H}\n255\n'.encode()+bytes(rgb),check=True)
