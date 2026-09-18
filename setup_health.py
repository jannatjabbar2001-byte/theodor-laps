from pathlib import Path
import shutil

src = Path('assets/images/45.png')
dst = Path('assets/images/health_icon.png')

if src.exists():
    shutil.copy2(src, dst)
    print('OK')
