# make_kneeboard_comm.py | v2.0.0  (src/KNEEBOARD/images/02_COMM.png; needs Pillow + DejaVu Sans Mono)
from PIL import Image, ImageDraw, ImageFont
W,H=512,768
BG=(248,244,234); BAND=(230,225,212); NAVY=(15,22,40); ORG=(232,150,20)
TXT=(30,30,30); GRN=(28,100,40); TAG=(182,118,0); GRY=(150,145,135); RULE=(210,206,196)
F="/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"; FB="/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"
f13=ImageFont.truetype(F,13); f11=ImageFont.truetype(F,11); fb11=ImageFont.truetype(FB,11); fT=ImageFont.truetype(FB,20); f10=ImageFont.truetype(F,10); fb10=ImageFont.truetype(FB,10)
im=Image.new("RGB",(W,H),BG); d=ImageDraw.Draw(im)
d.rectangle((0,0,W,42),fill=NAVY); d.rectangle((0,42,W,45),fill=ORG)
d.text((10,8),"02  COMM LADDER",font=fT,fill=ORG)
d.text((W-10,14),"CAS-1   SYRIA",font=f11,fill=(170,175,190),anchor="ra")
y=50
def band(t):
    global y
    d.rectangle((0,y,W,y+21),fill=BAND); d.text((10,y+3),t,font=f13,fill=TXT); y+=24
def row(ch,fq,name,tag,note=""):
    global y
    d.text((10,y+2),ch,font=f11,fill=GRY); d.text((30,y),fq,font=f13,fill=TXT)
    d.text((158,y),name,font=f13,fill=GRN)
    if note: d.text((W-48,y+2),note,font=f10,fill=GRY,anchor="ra")
    d.text((W-10,y+2),tag,font=fb11,fill=TAG,anchor="ra"); y+=18
def rule():
    global y
    y+=4; d.line((8,y,W-8,y),fill=RULE); y+=6
def head(t):
    global y
    d.rectangle((8,y,11,y+13),fill=TAG); d.text((16,y),t,font=fb11,fill=TXT); y+=18
band("COMM 1  (UFC → C1)   all AM")
row("01","262.00 AM","TOWER / PADDLES","TWR","CASE I/II zip")
row("02","269.00 AM","DEPARTURE","DEP")
row("03","265.00 AM","STRIKE","STK")
row("04","333.30 AM","POINTER 11","JTAC-1")
row("05","333.40 AM","EYEBALL 11","JTAC-2")
row("06","251.10 AM","OVERLORD","OVL")
row("07","252.10 AM","TEXACO 11","TKR")
row("15","263.00 AM","APPROACH","APP","+ CASE III LSO")
row("16","261.00 AM","MARSHAL","MRS","← CV COMMS")
rule()
band("COMM 2  (UFC → C2)")
row("01","251.10 AM","OVERLORD monitor","OVL")
row("02","128.10 AM","AI traffic","AI","ch 02–10: 128.10–128.90")
rule()
head("DISCRETE / GUARD")
d.text((10,y),"GUARD",font=f13,fill=TXT); d.text((180,y),"243.00 AM  (monitor)",font=f13,fill=GRY); y+=17
d.text((10,y),"ABORT (tac)",font=f13,fill=TXT); d.text((180,y),'JTAC: "abort, abort, abort"',font=f13,fill=TXT); y+=17
d.text((10,y),"CVN native ATC",font=f13,fill=TXT); d.text((180,y),"127.60 AM  not used (F1)",font=f13,fill=GRY); y+=17
rule()
head("COMM FLOW   (F10 CAS-1 COMMS / CV COMMS)")
flow=[("1","Airborne","DEP","C1-02","269.0","CASE III dep (I/II ZIPLIP)"),
("2","Cleared/7 DME","STK","C1-03","265.0","check in · Mode 4 · Kilo"),
("3","Strike h/o","OVL","C1-06","251.1","check in · picture"),
("4","20 NM to CP","PTR","C1-04","333.3","native JTAC"),
("5","Off Pointer","OVL","C1-06","251.1","→ EYE C1-05 333.4"),
("6","Off Eyeball","OVL","C1-06","251.1","INFLTREP → Texaco"),
("7","Texaco","TKR","C1-07","252.1","check in · refuel"),
("8","Off Texaco","OVL","C1-06","251.1","RTB · feet wet"),
("9","90 NM CVN","STK","C1-03","265.0","check in inbound"),
("10","50 NM CVN","MRS","C1-16","261.0","check in · readback"),
("11","Marshal h/o","APP","C1-15","263.0","CASE II/III approach"),
("12","See you at 10","TWR","C1-01","262.0","ZIPLIP (CASE I/II)")]
for n,a,b,c,fq,e in flow:
    d.text((10,y),n,font=f11,fill=TXT); d.text((30,y),a,font=f11,fill=TXT)
    d.text((134,y),"→",font=f11,fill=GRY); d.text((148,y),b,font=f11,fill=GRN)
    d.text((178,y),c,font=f11,fill=GRN); d.text((220,y),fq,font=f11,fill=GRN); d.text((268,y),e,font=f11,fill=TXT); y+=15
rule()
head("CV HOLD (CASE II/III)")
d.text((10,y),"R-196 / 25 DME / angels 10 · TCN 72X WSH · ICLS 12",font=f11,fill=TXT); y+=15
d.text((10,y),"CASE I: overhead, angels 2, port-beam commence",font=f11,fill=TXT); y+=15
print("bottom y",y)
d.line((8,H-24,W-8,H-24),fill=RULE)
d.text((10,H-18),"RESTRICTED   ·   FOR SIMULATION USE ONLY",font=f10,fill=GRY)
im.save(__import__("sys").argv[1] if len(__import__("sys").argv) > 1 else "02_COMM.png")
