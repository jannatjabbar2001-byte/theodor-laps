#!/usr/bin/env python3
import urllib.request
import os

os.chdir(r'c:\Users\angin\OneDrive\Desktop\مجلد جديد 0')

# صورة صحية حقيقية - أيقونة صحة خضراء
urls = [
    'https://images.unsplash.com/photo-1576091160550-112173f7f869?auto=format&fit=crop&w=800&q=90',
    'https://images.unsplash.com/photo-1631217b5f55-589a8fe93e96?auto=format&fit=crop&w=800&q=90',
]

output = 'assets/images/health_icon.png'

for url in urls:
    try:
        print(f'محاولة تنزيل من: {url}')
        urllib.request.urlretrieve(url, output)
        size = os.path.getsize(output) / 1024
        print(f'✓ تم حفظ صورة الصحة بنجاح!')
        print(f'✓ حجم الملف: {size:.2f} KB')
        break
    except Exception as e:
        print(f'✗ محاولة فشلت: {str(e)}')
        continue
