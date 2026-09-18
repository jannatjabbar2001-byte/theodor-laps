import requests
from pathlib import Path

# محاولة تنزيل صورة صحية مشابهة من مصدر موثوق
image_urls = [
    # صور صحية من Unsplash
    "https://images.unsplash.com/photo-1576091160550-112173f7f869?auto=format&fit=crop&w=900&q=85",  # صحة وعافية
    "https://images.unsplash.com/photo-1631217b5f55-589a8fe93e96?auto=format&fit=crop&w=900&q=85",  # أيقونة صحة
]

output_path = Path("assets/images/health_icon.png")

for url in image_urls:
    try:
        response = requests.get(url, timeout=5)
        if response.status_code == 200:
            with open(output_path, 'wb') as f:
                f.write(response.content)
            print(f"✓ تم حفظ الصورة بنجاح: {output_path}")
            print(f"✓ حجم الملف: {output_path.stat().st_size} بايت")
            exit(0)
    except Exception as e:
        print(f"✗ محاولة فشلت: {url} - {e}")
        continue

print("✗ فشل تنزيل الصورة من جميع المصادر")
