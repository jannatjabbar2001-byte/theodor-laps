# ثيودور لابز

منصة تعليمية متعددة المنصات مبنية بـ Flutter، مع خادم FastAPI للمصادقة والمحتوى.

## التشغيل المحلي

1. ثبّت اعتماديات Flutter: `flutter pub get`.
2. أنشئ البيئة الافتراضية وثبّت اعتماديات الخادم من `backend/requirements.txt`.
3. انسخ `backend/.env.example` إلى `backend/.env` وضع قيمة `JWT_SECRET`.
4. شغّل `run_app.bat`؛ سيبدأ الخادم ثم يفتح تطبيق Flutter على Chrome.

للتشغيل اليدوي، راجع [backend/README.md](backend/README.md).

## بنية المشروع

- `lib/`: تطبيق Flutter وواجهاته ومصادر الفيديو الخاصة بالمنصات.
- `assets/`: الصور والصوت المستخدمان داخل التطبيق.
- `backend/app/`: تطبيق FastAPI، نماذج قاعدة البيانات، والمصادقة والمسارات.
- `backend/media/`: ملفات الوسائط المحلية أثناء التطوير.
- `android/` و`web/`: ملفات المنصات الخاصة بـ Flutter.
- `APK_OUTPUT/` و`build/`: مخرجات البناء، ولا تُعد مصدرًا للتطبيق.

## بناء Web وAPK

- Web إنتاجي: `build_web.bat` مع ضبط `API_BASE_URL` على عنوان HTTPS.
- APK إنتاجي: `build_apk.bat` مع ضبط `API_BASE_URL` على عنوان HTTPS.
