#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import urllib.request
import ssl
import os
from pathlib import Path

os.chdir(r'c:\Users\angin\OneDrive\Desktop\مجلد جديد 0')

# تجاهل التحقق من SSL
ssl._create_default_https_context = ssl._create_unverified_context

# روابط صور صحية عالية الجودة
urls = [
    'https://images.unsplash.com/photo-1576091160550-112173f7f869?auto=format&fit=crop&w=800&q=90',
    'https://images.unsplash.com/photo-1631217b5f55-589a8fe93e96?auto=format&fit=crop&w=800&q=90',
    'https://images.unsplash.com/photo-1579154204601-01d430fe39e5?auto=format&fit=crop&w=800&q=90',
]

output_path = Path('assets/images/health_icon.png')
output_path.parent.mkdir(parents=True, exist_ok=True)

for url in urls:
    try:
        print(f'جاري التنزيل من: {url}')
        headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        }
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=15) as response:
            data = response.read()
            if len(data) > 10000:  # تأكد من أن الملف ليس صغير جداً
                with open(output_path, 'wb') as f:
                    f.write(data)
                size_kb = output_path.stat().st_size / 1024
                print(f'✓ تم حفظ صورة الصحة بنجاح!')
                print(f'✓ حجم الملف: {size_kb:.2f} KB')
                print(f'✓ المسار: {output_path.absolute()}')
                exit(0)
    except Exception as e:
        print(f'✗ فشل: {str(e)[:100]}')
        continue

print('✗ فشل تنزيل الصورة من جميع المصادر')
