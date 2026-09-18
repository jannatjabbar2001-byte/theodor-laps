#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import sys
import os

# تعيين مسار العمل
os.chdir(r'c:\Users\angin\OneDrive\Desktop\مجلد جديد 0')

try:
    import shutil
    source = os.path.abspath('assets/images/464.png')
    dest = os.path.abspath('assets/images/health_icon.png')
    
    if os.path.exists(source):
        shutil.copy2(source, dest)
        print(f'Success: {dest}')
        sys.exit(0)
    else:
        print(f'Source not found: {source}')
        sys.exit(1)
except Exception as e:
    print(f'Error: {str(e)}')
    sys.exit(1)
