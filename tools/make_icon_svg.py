import math, subprocess
from PIL import Image, ImageDraw, ImageFont

def squircle(cx, cy, r, n=5.0, steps=240):
    pts=[]
    for i in range(steps):
        t=2*math.pi*i/steps
        c,s=math.cos(t),math.sin(t)
        x=cx+r*math.copysign(abs(c)**(2/n),c)
        y=cy+r*math.copysign(abs(s)**(2/n),s)
        pts.append(f"{x:.1f},{y:.1f}")
    return "M"+" L".join(pts)+" Z"

def finger(x, top, w=92, bottom=600):
    return f'<rect x="{x}" y="{top}" width="{w}" height="{bottom-top}" rx="{w/2}"/>'

THUMB = ("M300,708 C400,664 536,606 616,580 "
         "A50,50 0 0 1 660,672 "
         "C566,712 440,778 300,846 Z")

def hand_mask():
    """White = hand, black = cut lines (finger gaps, knuckles, thumb outline)."""
    fingers = finger(352, 250, 92, 640) + finger(458, 200, 92, 640) + finger(564, 236, 92, 640)
    palm = '<path d="M352,520 L640,520 Q680,524 680,576 L680,776 Q680,846 612,874 L612,1024 L412,1024 L412,874 Q352,846 352,776 Z"/>'
    gaps = '<path d="M451,512 L451,552 M557,512 L557,548" stroke="black" stroke-width="14"/>'
    thumb = ('<g clip-path="url(#thumbclip)">'
             f'<path d="{THUMB}" fill="black" stroke="black" stroke-width="40" stroke-linejoin="round"/>'
             f'<path d="{THUMB}" fill="white"/></g>')
    return f'<mask id="handmask" maskUnits="userSpaceOnUse" x="-500" y="-500" width="2048" height="2048"><g fill="white">{fingers}{palm}</g>{gaps}{thumb}</mask>'

def hand(fill="white"):
    return f'<rect x="-500" y="-500" width="2048" height="2048" fill="{fill}" mask="url(#handmask)"/>'

def icon(variant):
    body = squircle(512, 512, 412)
    if variant == "A":
        stops = [("0", "#0B1E46"), ("0.55", "#1A4FB8"), ("1", "#3D8BFF")]
        extra, shadow = "", ""
        hand_tf = 'transform="translate(512 560) scale(1.12) translate(-512 -560)"'
    elif variant == "B":
        stops = [("0", "#061433"), ("0.6", "#123E9C"), ("1", "#2F6BFF")]
        extra = '<circle cx="512" cy="560" r="330" fill="url(#glow)"/>'
        hand_tf = 'transform="translate(512 560) scale(1.1) translate(-512 -560) rotate(-9 512 600)"'
        shadow = f'<g transform="translate(18 26) translate(512 560) scale(1.1) translate(-512 -560) rotate(-9 512 600)" opacity="0.35" filter="url(#blur)">{hand("#020A1F")}</g>'
    else:
        stops = [("0", "#0E2A5C"), ("0.5", "#1E64C8"), ("1", "#36B4F0")]
        extra = '<circle cx="512" cy="560" r="318" fill="white" opacity="0.13"/><circle cx="512" cy="560" r="318" fill="none" stroke="white" stroke-opacity="0.35" stroke-width="6"/>'
        hand_tf = 'transform="translate(512 600) scale(0.98) translate(-512 -600)"'
        shadow = ""
    st = "".join(f'<stop offset="{o}" stop-color="{c}"/>' for o, c in stops)
    cut = "url(#bg)"
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<defs>
<linearGradient id="bg" gradientUnits="userSpaceOnUse" x1="200" y1="100" x2="824" y2="924">{st}</linearGradient>
<radialGradient id="glow" cx="0.5" cy="0.45" r="0.5"><stop offset="0" stop-color="#7FB4FF" stop-opacity="0.45"/><stop offset="1" stop-color="#7FB4FF" stop-opacity="0"/></radialGradient>
<radialGradient id="shine" cx="0.25" cy="0.15" r="0.7"><stop offset="0" stop-color="white" stop-opacity="0.16"/><stop offset="1" stop-color="white" stop-opacity="0"/></radialGradient>
<filter id="blur" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="14"/></filter>
<clipPath id="thumbclip"><rect x="352" y="0" width="700" height="1024"/></clipPath>
{hand_mask()}
<clipPath id="clip"><path d="{body}"/></clipPath>
</defs>
<g clip-path="url(#clip)">
<rect width="1024" height="1024" fill="url(#bg)"/>
<rect width="1024" height="1024" fill="url(#shine)"/>
{extra}
{shadow}
<g {hand_tf}>{hand()}</g>
</g>
<path d="{body}" fill="none" stroke="white" stroke-opacity="0.18" stroke-width="3"/>
</svg>'''

def menubar(color):
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="322 180 388 720">
<defs><clipPath id="tc"><rect x="352" y="0" width="700" height="1024"/></clipPath><mask id="m"><rect x="0" y="0" width="1024" height="1024" fill="white"/>
<path d="{THUMB}" fill="black" stroke="black" stroke-width="90" stroke-linejoin="round"/>
<path d="M451,500 L451,560 M557,500 L557,556" stroke="black" stroke-width="30" stroke-linecap="round"/></mask></defs>
<g fill="{color}" mask="url(#m)">{finger(352,250,92,640)}{finger(458,200,92,640)}{finger(564,236,92,640)}
<path d="M352,520 L640,520 Q680,524 680,576 L680,776 Q680,846 612,874 L612,900 L412,900 L412,874 Q352,846 352,776 Z"/></g>
<g clip-path="url(#tc)"><path d="{THUMB}" fill="{color}"/></g>
</svg>'''

for v in "ABC":
    open(f"/tmp/icons/{v}.svg","w").write(icon(v))
    subprocess.run(["rsvg-convert","-w","1024","-h","1024",f"/tmp/icons/{v}.svg","-o",f"/tmp/icons/{v}.png"],check=True)
for name,col in (("mb_black","black"),("mb_white","white")):
    open(f"/tmp/icons/{name}.svg","w").write(menubar(col))
    subprocess.run(["rsvg-convert","-h","72",f"/tmp/icons/{name}.svg","-o",f"/tmp/icons/{name}.png"],check=True)
print("ok")
