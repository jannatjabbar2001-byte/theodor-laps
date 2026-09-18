from PIL import Image, ImageDraw, ImageFont
import os

os.chdir(r'c:\Users\angin\OneDrive\Desktop\مجلد جديد 0')

# إنشاء صورة صحية خضراء 512x512
img = Image.new('RGB', (512, 512), color=(45, 85, 45))
draw = ImageDraw.Draw(img)

# رسم دائرة خارجية بيضاء
draw.ellipse([10, 10, 502, 502], outline=(200, 255, 200), width=12)

# رسم دائرة خضراء فاتحة
draw.ellipse([20, 20, 492, 492], outline=(120, 200, 120), width=8)

# رسم قلب أخضر في المركز
heart_x, heart_y = 256, 220
# رسم فصوص القلب
draw.ellipse([heart_x - 60, heart_y - 60, heart_x - 10, heart_y], fill=(100, 180, 100), outline=(150, 200, 150), width=2)
draw.ellipse([heart_x + 10, heart_y - 60, heart_x + 60, heart_y], fill=(100, 180, 100), outline=(150, 200, 150), width=2)
# رسم حافة القلب
draw.polygon([(heart_x - 60, heart_y - 20), (heart_x + 60, heart_y - 20), (heart_x, heart_y + 80)], fill=(100, 180, 100))

# رسم خط نبض (ECG line)
ecg_y = 280
ecg_color = (255, 255, 255)
points = []
for i in range(50, 450, 10):
    if i < 150:
        y = ecg_y - 20
    elif i < 200:
        y = ecg_y - 40
    elif i < 250:
        y = ecg_y
    elif i < 300:
        y = ecg_y + 30
    elif i < 350:
        y = ecg_y
    else:
        y = ecg_y - 20
    points.append((i, y))

if len(points) > 1:
    draw.line(points, fill=ecg_color, width=3)

# رسم علامة (+) بيضاء
plus_x, plus_y = 380, 260
draw.rectangle([plus_x - 20, plus_y - 3, plus_x + 20, plus_y + 3], fill=(255, 255, 255))
draw.rectangle([plus_x - 3, plus_y - 20, plus_x + 3, plus_y + 20], fill=(255, 255, 255))

# رسم يد بيضاء في الأسفل
hand_x, hand_y = 200, 380
draw.arc([hand_x - 40, hand_y - 60, hand_x + 40, hand_y], 0, 180, fill=(200, 200, 200), width=15)
draw.ellipse([hand_x - 50, hand_y - 20, hand_x + 50, hand_y + 40], fill=(220, 220, 220), outline=(200, 200, 200), width=2)

# حفظ الصورة
img.save('assets/images/health_icon.png')
print('Image created successfully')
