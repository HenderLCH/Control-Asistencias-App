import json
import urllib.request
import urllib.error

SUPABASE_URL = 'https://mkhcmfjyowketdahadvt.supabase.co'
SUPABASE_KEY = 'sb_publishable_fmS5vAc6n1gspsDUhE7-1w_yqQPAfpf'

passwords_to_test = [
    'CNSC-2026-MSyW',
    '',
    '123456',
    '12345678',
    'admin123',
    'coordinador2026',
    'cnsc2026',
]

for pwd in passwords_to_test:
    auth_url = f'{SUPABASE_URL}/auth/v1/token?grant_type=password'
    payload = json.dumps({'email': 'ludytibisay@gmail.com', 'password': pwd}).encode()
    req = urllib.request.Request(auth_url, data=payload, headers={'apikey': SUPABASE_KEY, 'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req) as r:
            print(f'Auth token login with "{pwd}": SUCCESS!')
            break
    except urllib.error.HTTPError as e:
        print(f'Auth token login with "{pwd}": FAILED ({e.code})')
