"""Builds an illustrative UI concept and a synthetic scanned/cleaned note sample.
This is not an emulator screenshot or the Android build result.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import numpy as np
import math, random
from reportlab.pdfgen import canvas
from reportlab.lib.utils import ImageReader

root=Path(__file__).resolve().parents[1]
assets=root/'samples'; assets.mkdir(exist_ok=True)
font='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
fontb='/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
hand='/usr/share/fonts/opentype/comic-neue/ComicNeue-Regular.otf'
handb='/usr/share/fonts/opentype/comic-neue/ComicNeue-Bold.otf'
def f(path,size):return ImageFont.truetype(path,size)
# Simulate a real photographed student notebook, with natural imperfect blue pen strokes.
w,h=830,1130
source=Image.new('RGB',(w,h),(223,215,198)); d=ImageDraw.Draw(source)
rng=random.Random(11)
for y in range(0,h,34):
 d.line((28,y+22,w-20,y+22),fill=(175,189,192),width=1)
d.line((99,25,99,h-40),fill=(187,145,139),width=2)
ink=(38,62,117)
rows=[('Physics - Simple harmonic motion',55,45),('Consider a mass attached to a spring.',52,118),('Restoring force: F = -kx',53,184),('Newton: m x\'\' = -kx',53,250),('=> x\'\' + (k/m) x = 0',53,317),('General solution:',53,395),('x(t) = A cos(wt + phi)',53,462),('w = sqrt(k/m)',53,532),('Amplitude A depends on initial conditions.',53,602),('Frequency f = w / (2*pi)',53,679),('Energy: E = (1/2) k A^2',53,760)]
for txt,x,y in rows:
 d.text((x+rng.randint(-3,3),y),txt,font=f(handb if y==45 else hand,30 if y==45 else 29),fill=ink)
# Hand drawn colored spring diagram at bottom.
d.rounded_rectangle((185,832,230,950),radius=12,fill=(130,146,156),outline=(56,83,112),width=3)
d.line((230,886,260,886),fill=(50,70,112),width=4)
pts=[]
for t in range(11):
 x=260+t*30; y=886+((-1)**t)*18; pts.append((x,y))
d.line(pts,fill=(37,81,148),width=4,joint='curve')
d.rectangle((580,839,689,930),outline=(177,84,51),width=5,fill=(248,216,191))
d.text((612,858),'m',font=f(handb,39),fill=(151,73,44))
d.line((635,937,635,977),fill=(177,84,51),width=3)
d.polygon(((635,980),(626,963),(644,963)),fill=(177,84,51))
d.text((655,951),'x',font=f(hand,28),fill=(177,84,51))
d.text((60,1040),'Diagram: spring - mass system',font=f(hand,28),fill=ink)
# Add subtle uneven illumination, vignetting and noise.
arr=np.asarray(source).astype('float32')
y,x=np.ogrid[:h,:w]
shade=(x/w*.09+y/h*.13+((x/w-.5)**2+(y/h-.5)**2)*.18)
noise=np.random.default_rng(4).normal(0,2.5,(h,w,1))
arr=np.clip(arr*(1-shade[...,None])+noise,0,255).astype('uint8')
Image.fromarray(arr).save(assets/'example_photo.jpg',quality=90)
# Approximate paper cleaning as implemented in Flutter, retaining original ink and diagram pixels.
pix=arr.astype('float32'); lum=pix[...,0]*.2126+pix[...,1]*.7152+pix[...,2]*.0722
# Preview approximation: a broad Gaussian low-pass estimates uneven paper light.
blur=Image.fromarray(np.uint8(np.clip(lum,0,255))).filter(ImageFilter.GaussianBlur(radius=60))
local=np.clip(np.asarray(blur).astype('float32'),75,255)
# Smooth brightening; true Flutter code uses a small-cell bright-background estimator.
gain=np.clip(251/local,.85,2.3)
cl=np.clip(lum*gain,0,255)
lift=np.where(cl>206,cl+(255-cl)*.58,cl)
clean=np.clip(lift[...,None]+(pix-lum[...,None])*gain[...,None]*1.07,0,255).astype('uint8')
Image.fromarray(clean).save(assets/'example_cleaned.jpg',quality=91)
# Proper A4 image PDF for reviewing the visual output.
pdf=canvas.Canvas(str(assets/'sample_export.pdf'),pagesize=(595,842))
raw=Image.open(assets/'example_cleaned.jpg'); iw,ih=raw.size
fit=min(560/iw,808/ih)
w2,h2=iw*fit,ih*fit
pdf.drawImage(ImageReader(raw),(595-w2)/2,(842-h2)/2,width=w2,height=h2)
pdf.showPage();pdf.save()

# Marketing-style UI mockup visually aligned with the Flutter code; explicitly labeled illustrative.
navy='#101F32';teal='#087D83';aqua='#DCF4F0';mute='#6F8190';paper='#F6F7F4'
W,H=1040,1650
out=Image.new('RGB',(W,H),'#DFE6E2');dr=ImageDraw.Draw(out)
def rounded(box,r,fill,outline=None,width=1):dr.rounded_rectangle(box,radius=r,fill=fill,outline=outline,width=width)
def text(x,y,t,size,color,heavy=False):dr.text((x,y),t,font=f(fontb if heavy else font,size),fill=color)
# large single-phone app screen with enough resolution for presentation
px,py,pw,ph=225,46,590,1510
rounded((px-7,py-7,px+pw+7,py+ph+7),56,'#263C48')
rounded((px,py,px+pw,py+ph),50,paper)
rounded((px+225,py+9,px+365,py+23),10,'#263C48')
text(px+38,py+51,'NoteCraft',31,navy,True);text(px+40,py+91,'STUDY STUDIO',13,mute,True)
rounded((px+432,py+60,px+548,py+102),20,aqua);text(px+455,py+70,'OFFLINE',14,teal,True)
for i,(lbl,left) in enumerate([('Scan',25),('Insights',211),('Settings',397)]):
 x=px+left;rounded((x,py+135,x+169,py+197),14,navy if i==0 else 'white')
 text(x+45,py+151,lbl,19,'white' if i==0 else mute,True)
text(px+30,py+233,'01 / CAPTURE + REFINE',15,teal,True)
text(px+30,py+265,'Your note workspace',29,navy,True)
rounded((px+26,py+324,px+292,py+399),14,teal);text(px+73,py+346,'Take photo',22,'white',True)
rounded((px+302,py+324,px+563,py+399),14,'white',outline='#D6E3E2',width=2)
text(px+344,py+346,'Add pages',22,navy,True)
rounded((px+26,py+421,px+563,py+1089),19,'#E7EBE8')
scan=Image.open(assets/'example_cleaned.jpg')
scan.thumbnail((492,612))
out.paste(scan,(px+int((590-scan.width)/2),py+442))
dr=ImageDraw.Draw(out)
rounded((px+45,py+445,px+221,py+478),5,navy)
text(px+55,py+453,'PAGE 1 / 3',13,'white',True)
rounded((px+30,py+1109,px+205,py+1166),12,teal)
text(px+43,py+1127,'Clean paper',17,'white',True)
rounded((px+216,py+1109,px+383,py+1166),12,'white',outline='#DCE4E3',width=2)
text(px+228,py+1127,'Color boost',17,navy,True)
rounded((px+393,py+1109,px+563,py+1166),12,'white',outline='#DCE4E3',width=2)
text(px+421,py+1127,'Black ink',17,navy,True)
text(px+30,py+1212,'03 / SAVE + SHARE',15,teal,True)
text(px+30,py+1244,'Choose output format',29,navy,True)
rounded((px+26,py+1301,px+290,py+1414),15,'white',outline='#DDE7E3',width=2)
rounded((px+302,py+1301,px+563,py+1414),15,'white',outline='#DDE7E3',width=2)
text(px+44,py+1331,'Export PDF',21,navy,True)
text(px+44,py+1366,'Multi-page file',15,mute)
text(px+319,py+1331,'Export images',21,navy,True)
text(px+319,py+1366,'JPEG files',15,mute)
text(32,17,'ILLUSTRATIVE INTERFACE PREVIEW  -  NOT A DEVICE SCREENSHOT',18,'#4E6674',True)
path=root/'NoteCraft_App_Preview.png';out.save(path)
# Side-by-side quick before/after visual sample.
comp=Image.new('RGB',(1040,720),'#F6F7F4');draw=ImageDraw.Draw(comp)
left=Image.open(assets/'example_photo.jpg');right=Image.open(assets/'example_cleaned.jpg')
left.thumbnail((480,620));right.thumbnail((480,620))
comp.paste(left,(25,72));comp.paste(right,(540,72))
draw.text((25,20),'BEFORE / PHOTO',font=f(fontb,22),fill=navy)
draw.text((540,20),'AFTER / ENHANCED',font=f(fontb,22),fill=teal)
comp.save(root/'NoteCraft_Before_After.jpg',quality=90)
print('Made mockup and sample images/PDF')
