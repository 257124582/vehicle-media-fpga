"""Compose exact software reference panels, never represent them as board captures."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[1]
canvas=Image.new('RGB',(960,572),(16,24,32));draw=ImageDraw.Draw(canvas)
try:font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',18)
except OSError:font=ImageFont.load_default()
names=['ORIGINAL','GRAYSCALE','BINARY 128','SOBEL','BRIGHTNESS +32','CONTRAST 1.5x']
for md,name in enumerate(names):
 x=(md%3)*320;y=(md//3)*272
 im=Image.open(ROOT/f'assets/reference/01_DAY_mode{md}.png').convert('RGB').resize((320,240),Image.Resampling.NEAREST)
 canvas.paste(im,(x,y+32));draw.text((x+10,y+7),f'{md}: {name}',font=font,fill=(80,235,225))
draw.text((10,550),'SOFTWARE REFERENCE - NOT A BOARD OR DISPLAY CAPTURE',font=font,fill=(200,210,220))
canvas.save(ROOT/'assets/reference/algorithm_preview.png')
