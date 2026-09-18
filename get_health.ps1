@"
`$url = 'https://images.unsplash.com/photo-1576091160550-112173f7f869?auto=format&fit=crop&w=800&q=90'
`$out = 'C:\Users\angin\OneDrive\Desktop\مجلد جديد 0\assets\images\health_icon.png'
`$ProgressPreference = 'SilentlyContinue'
Invoke-WebRequest -Uri `$url -OutFile `$out
Write-Host 'Done'
"@ | powershell -NoProfile -
