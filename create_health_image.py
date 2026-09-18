from PIL import Image, ImageDraw
from pathlib import Path

# إنشاء صورة صحية بخلفية خضراء
output_path = Path("assets/images/health_icon.png")

# تحديد حجم الصورة
width, height = 512, 512
background = (45, 85, 45)  # أخضر غامق

# إنشاء صورة جديدة
img = Image.new('RGB', (width, height), background)
draw = ImageDraw.Draw(img)

# رسم دائرة خارجية خضراء فاتحة
circle_color = (120, 200, 120)  # أخضر فاتح
draw.ellipse([20, 20, 492, 492], outline=circle_color, width=15)

# رسم قلب أخضر في المركز
heart_x, heart_y = 256, 256
heart_size = 100
# رسم قلب بسيط
draw.ellipse([heart_x - 60, heart_y - 50, heart_x - 10, heart_y], fill=(100, 180, 100), outline=(200, 255, 100), width=3)
draw.ellipse([heart_x + 10, heart_y - 50, heart_x + 60, heart_y], fill=(100, 180, 100), outline=(200, 255, 100), width=3)
draw.polygon([(heart_x - 60, heart_y - 20), (heart_x + 60, heart_y - 20), (heart_x, heart_y + 60)], fill=(100, 180, 100))

# حفظ الصورة
img.save(output_path)
print(f"✓ تم إنشاء الصورة بنجاح: {output_path}")
print(f"✓ حجم الملف: {output_path.stat().st_size} بايت")
