import requests

url = 'https://images.unsplash.com/photo-1576091160550-112173f7f869?auto=format&fit=crop&w=800&q=90'
output = r'c:\Users\angin\OneDrive\Desktop\مجلد جديد 0\assets\images\health_icon.png'

try:
    r = requests.get(url, timeout=10)
    if r.status_code == 200:
        with open(output, 'wb') as f:
            f.write(r.content)
        print('OK')
except:
    pass
