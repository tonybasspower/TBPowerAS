# TBPower – icona app: chip stilizzato con sfumatura del logo TBP; glifo barra dei menu da /workspace/tbp-logo-gradient.jpg (mela gradiente blu-viola, foglia ciano, "TBP" argento)
from PIL import Image, ImageFilter, ImageDraw, ImageFont
import numpy as np
from scipy import ndimage

SRC = '/workspace/tbp-logo-gradient.jpg'
FONT = '/usr/share/fonts/truetype/sand-box/google/Inter/Inter-VariableFont_opsz,wght.ttf'
srcim = Image.open(SRC).convert('RGB')
a = np.asarray(srcim).astype(np.float32)

# --- maschera del logo: pixel colorati o luminosi rispetto allo sfondo quasi nero ---
sat = a.max(2) - a.min(2); lum = a.mean(2)
fg = (sat > 45) | (lum > 70)
fg = ndimage.binary_opening(fg, iterations=1)
lab, n = ndimage.label(fg)
sizes = ndimage.sum(fg, lab, range(1, n+1))
keep = np.isin(lab, 1 + np.where(sizes > 300)[0])       # solo mela, foglia, lettere
ys, xs = np.where(keep)
y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
print('logo bbox', x0, x1, y0, y1)

# --- glifo template: silhouette piena (mela + foglia) con "TBP" scavato ---
solid = ndimage.binary_fill_holes(keep)
lum_n = lum
letters = (lum_n > 110) & (sat < 40) & solid               # argento delle lettere
letters = ndimage.binary_dilation(letters, iterations=2)
glyph = solid & ~letters
pad = 4
gcrop = glyph[y0-pad:y1+pad+1, x0-pad:x1+pad+1].astype(np.float32)
g = Image.fromarray((gcrop*255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))
for scale, name in [(1, 'MenuBarIcon.png'), (2, 'MenuBarIcon@2x.png')]:
    h = 18*scale; w = round(g.width*h/g.height)
    m = g.resize((w*4, h*4), Image.LANCZOS).resize((w, h), Image.LANCZOS)
    m = m.point(lambda v: 0 if v < 40 else min(255, int((v-40)*255/150)))
    im = Image.new('RGBA', (w, h), (0,0,0,255)); im.putalpha(m); im.save(name); print(name, im.size)

# --- icona 1024 ---
N, BODY = 1024, 824; OFF = (N-BODY)//2
def squircle(size, n=5.0, ss=4):
    s = size*ss; yy, xx = np.mgrid[0:s, 0:s].astype(np.float32)
    u = np.abs((xx+0.5)/s*2-1); v = np.abs((yy+0.5)/s*2-1)
    return Image.fromarray((((u**n+v**n) <= 1)*255).astype(np.uint8)).resize((size,size), Image.LANCZOS)
sq = squircle(BODY)

# sfondo antracite quasi nero con vignettatura radiale (colori campionati dalla sorgente)
yy, xx = np.mgrid[0:BODY, 0:BODY].astype(np.float32)/BODY
r = np.sqrt((xx-0.5)**2 + (yy-0.44)**2)
centre = np.array([22, 26, 32], np.float32); edge = np.array([6, 9, 11], np.float32)
t = np.clip(r/0.72, 0, 1)**1.4
bgarr = centre*(1-t[...,None]) + edge*t[...,None]

# --- chip/processore stilizzato (pin sui 4 lati, angoli arrotondati, quadrato interno) ---
SS = 4; C = BODY*SS
m = Image.new('L', (C, C), 0); d = ImageDraw.Draw(m)
cx, cy = C//2, int(C*0.40)                 # centro del chip (lascia spazio alla scritta)
half = int(C*0.215); stroke = int(C*0.042); rad = int(C*0.06)
box = (cx-half, cy-half, cx+half, cy+half)
d.rounded_rectangle(box, rad, fill=255)
d.rounded_rectangle((box[0]+stroke, box[1]+stroke, box[2]-stroke, box[3]-stroke), max(rad-stroke, 1), fill=0)
ih = int(half*0.50); ist = int(stroke*0.85)  # quadrato interno con "pallino" in alto a sinistra
ib = (cx-ih, cy-ih, cx+ih, cy+ih)
d.rounded_rectangle(ib, int(ih*0.28), fill=255)
d.rounded_rectangle((ib[0]+ist, ib[1]+ist, ib[2]-ist, ib[3]-ist), int(ih*0.12), fill=0)
dr = int(ih*0.16); dx, dy = ib[0]+ist+int(ih*0.32), ib[1]+ist+int(ih*0.32)
d.ellipse((dx-dr, dy-dr, dx+dr, dy+dr), fill=255)
npin = 5; plen = int(C*0.07); pw = int(C*0.026); gap = int(C*0.02)
span = 2*half - 2*rad - pw
for k in range(npin):
    o = -half + rad + pw//2 + int(span*k/(npin-1))
    for (x0_, y0_, x1_, y1_) in [
        (cx+o-pw//2, box[1]-gap-plen, cx+o+pw//2, box[1]-gap),
        (cx+o-pw//2, box[3]+gap, cx+o+pw//2, box[3]+gap+plen),
        (box[0]-gap-plen, cy+o-pw//2, box[0]-gap, cy+o+pw//2),
        (box[2]+gap, cy+o-pw//2, box[2]+gap+plen, cy+o+pw//2)]:
        d.rounded_rectangle((x0_, y0_, x1_, y1_), pw//2, fill=255)
cm = m.resize((BODY, BODY), Image.LANCZOS)
ca = np.asarray(cm).astype(np.float32)/255
# sfumatura diagonale azzurro -> viola (palette del logo TBP)
g = np.clip((xx*0.55 + yy*0.45 - 0.18)/0.62, 0, 1)[..., None]
cyan = np.array([64, 196, 255], np.float32); violet = np.array([150, 70, 255], np.float32)
grad = cyan*(1-g) + violet*g
# alone morbido
glow = np.asarray(cm.filter(ImageFilter.GaussianBlur(26))).astype(np.float32)/255*0.55
bgarr = bgarr*(1-glow[..., None]) + grad*0.55*glow[..., None] + bgarr*0.45*glow[..., None]
# luce sul bordo superiore del tratto
hi = np.clip(1 - (yy - 0.18)/0.5, 0, 1)[..., None]*0.18
col = grad*(1-hi) + 255*hi
bgarr = bgarr*(1-ca[..., None]) + col*ca[..., None]

body = Image.fromarray(np.clip(bgarr, 0, 255).astype(np.uint8), 'RGB').convert('RGBA')

# testo "TBPower" argento metallico
font = ImageFont.truetype(FONT, 104)
try: font.set_variation_by_axes([32, 700])   # opsz, wght
except Exception: font.set_variation_by_name('Bold')
txt = "TBPower"
bb = font.getbbox(txt); tw, th = bb[2]-bb[0], bb[3]-bb[1]
tmask = Image.new('L', (tw+20, th+20), 0)
ImageDraw.Draw(tmask).text((10-bb[0], 10-bb[1]), txt, font=font, fill=255)
gy = np.linspace(0, 1, tmask.height)[:, None]
silver = np.interp(gy, [0, 0.45, 0.55, 1], [250, 205, 170, 225])
metal = np.repeat(silver, tmask.width, 1)
metal_rgb = np.stack([metal-6, metal-3, metal+2], 2).clip(0, 255).astype(np.uint8)
timg = Image.fromarray(metal_rgb, 'RGB').convert('RGBA'); timg.putalpha(tmask)
shadow = Image.new('RGBA', tmask.size, (0,0,0,255)); shadow.putalpha(tmask.filter(ImageFilter.GaussianBlur(4)).point(lambda v: int(v*0.7)))
tx = (BODY-tmask.width)//2; ty = int(BODY*0.785) - tmask.height//2
body.alpha_composite(shadow, (tx, ty+4)); body.alpha_composite(timg, (tx, ty))

# bordo interno sottile chiaro (rifinitura stile Big Sur)
edge_m = np.asarray(sq).astype(np.float32)
inner = ndimage.binary_erosion(edge_m > 128, iterations=3)
ring = ((edge_m > 128) & ~inner).astype(np.float32)*0.10
ba = np.asarray(body).astype(np.float32)
ba[..., :3] = ba[..., :3]*(1-ring[...,None]) + 255*ring[...,None]
ba[..., 3] = edge_m
body = Image.fromarray(ba.clip(0, 255).astype(np.uint8), 'RGBA')

canvas = Image.new('RGBA', (N, N), (0,0,0,0))
sh = Image.new('L', (N, N), 0); sh.paste(sq, (OFF, OFF+12))
sh = sh.filter(ImageFilter.GaussianBlur(14)).point(lambda v: int(v*0.5))
s = Image.new('RGBA', (N, N), (0,0,0,255)); s.putalpha(sh)
canvas.alpha_composite(s); canvas.alpha_composite(body, (OFF, OFF))
canvas.save('AppIcon-1024.png')
import os; os.makedirs('sizes', exist_ok=True)
for sz in [16, 32, 64, 128, 256, 512, 1024]:
    canvas.resize((sz, sz), Image.LANCZOS).save(f'sizes/icon_{sz}.png')
print('ok')

# --- glifo template "chip" per la barra dei menu (18 pt, @1x/@2x), nero su trasparente ---
def chip_glyph(px):
    S = 8; C = px*S
    m = Image.new('L', (C, C), 0); d = ImageDraw.Draw(m)
    c = C/2; half = C*0.30; st = C*0.085; rad = C*0.08
    box = (c-half, c-half, c+half, c+half)
    d.rounded_rectangle(box, rad, fill=255)
    d.rounded_rectangle((box[0]+st, box[1]+st, box[2]-st, box[3]-st), max(rad-st, 1), fill=0)
    ih = half*0.42
    d.rounded_rectangle((c-ih, c-ih, c+ih, c+ih), ih*0.3, fill=255)   # die interno pieno
    npin = 3; plen = C*0.13; pw = C*0.07; gap = C*0.035
    for k in range(npin):
        o = (-1 + k) * half*0.55
        for r in [(c+o-pw/2, box[1]-gap-plen, c+o+pw/2, box[1]-gap),
                  (c+o-pw/2, box[3]+gap, c+o+pw/2, box[3]+gap+plen),
                  (box[0]-gap-plen, c+o-pw/2, box[0]-gap, c+o+pw/2),
                  (box[2]+gap, c+o-pw/2, box[2]+gap+plen, c+o+pw/2)]:
            d.rounded_rectangle(r, pw/2, fill=255)
    m = m.resize((px, px), Image.LANCZOS)
    im = Image.new('RGBA', (px, px), (0, 0, 0, 255)); im.putalpha(m); return im
chip_glyph(18).save('MenuBarChip.png'); chip_glyph(36).save('MenuBarChip@2x.png'); print('chip glyph ok')
