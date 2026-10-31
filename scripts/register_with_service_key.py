# -*- coding: utf-8 -*-
"""
Registers all teachers in Supabase using the admin service_role key:
- POST /auth/v1/admin/users (auto-confirmed, zero rate limits)
- Upserts profiles table with [FORCE_PWD_CHANGE][PWD:<password>]
- Leaves all classrooms unassigned
"""

import json
import random
import urllib.request
import datetime

SUPABASE_URL = 'https://mkhcmfjyowketdahadvt.supabase.co'
SERVICE_KEY = os.environ.get('SUPABASE_SERVICE_KEY', '')

TEACHERS = [
    ('prof.andernazaret@gmail.com', 'Anderson Duque'),
    ('profeangelik2@gmail.com', 'Angelica Moreno'),
    ('coritonazaret90@gmail.com', 'Coromoto Ramirez'),
    ('dianaurd0412@gmail.com', 'Diana Urdaneta'),
    ('eluzquiroz@gmail.com', 'Eluz Quiroz'),
    ('jenni.idarraga@gmail.com', 'Jennifer Idarraga'),
    ('jennifermarquez@gmail.com', 'Jennifer Marquez'),
    ('nazaretmarialejandra@gmail.com', 'María Pernía'),
    ('ninfa.nazaret@gmail.com', 'Ninfa Labrador'),
    ('idarragayoselin@gmail.com', 'Joselin Idarraga'),
    ('robertnieto277@gmail.com', 'Rober Nieto'),
    ('nazaretsandrap2025@gmail.com', 'Sandra Vivas'),
]

def generate_8char_password():
    upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
    lower = 'abcdefghijkmnpqrstuvwxyz'
    digits = '23456789'
    specials = '.!@#*'
    all_chars = upper + lower + digits + specials

    chars = [
        random.choice(upper),
        random.choice(lower),
        random.choice(digits),
        random.choice(specials),
    ]
    while len(chars) < 8:
        chars.append(random.choice(all_chars))
    random.shuffle(chars)
    return ''.join(chars)

def get_existing_auth_users():
    req = urllib.request.Request(
        f'{SUPABASE_URL}/auth/v1/admin/users',
        headers={'apikey': SERVICE_KEY, 'Authorization': f'Bearer {SERVICE_KEY}'}
    )
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read().decode())
        users = data.get('users', [])
        return {u['email'].lower(): u for u in users if u.get('email')}

def create_or_update_auth_user(existing_users, email, full_name, password):
    clean_email = email.strip().lower()
    if clean_email in existing_users:
        u = existing_users[clean_email]
        user_id = u['id']
        # Update user password and metadata
        url = f'{SUPABASE_URL}/auth/v1/admin/users/{user_id}'
        payload = json.dumps({
            'password': password,
            'email_confirm': True,
            'user_metadata': {'full_name': full_name, 'role': 'profesor'}
        }).encode()
        req = urllib.request.Request(
            url,
            data=payload,
            headers={
                'apikey': SERVICE_KEY,
                'Authorization': f'Bearer {SERVICE_KEY}',
                'Content-Type': 'application/json'
            },
            method='PUT'
        )
        with urllib.request.urlopen(req) as resp:
            return user_id
    else:
        # Create user
        url = f'{SUPABASE_URL}/auth/v1/admin/users'
        payload = json.dumps({
            'email': clean_email,
            'password': password,
            'email_confirm': True,
            'user_metadata': {'full_name': full_name, 'role': 'profesor'}
        }).encode()
        req = urllib.request.Request(
            url,
            data=payload,
            headers={
                'apikey': SERVICE_KEY,
                'Authorization': f'Bearer {SERVICE_KEY}',
                'Content-Type': 'application/json'
            }
        )
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode())
            return data['id']

def upsert_profile(user_id, email, full_name, password):
    url = f'{SUPABASE_URL}/rest/v1/profiles'
    headers = {
        'apikey': SERVICE_KEY,
        'Authorization': f'Bearer {SERVICE_KEY}',
        'Content-Type': 'application/json',
        'Prefer': 'resolution=merge-duplicates'
    }
    phone_val = f'[FORCE_PWD_CHANGE][PWD:{password}]'
    payload = json.dumps({
        'id': user_id,
        'email': email.strip().lower(),
        'full_name': full_name.strip(),
        'role': 'profesor',
        'phone': phone_val,
        'is_active': True,
        'updated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    }).encode('utf-8')
    req = urllib.request.Request(url, data=payload, headers=headers)
    with urllib.request.urlopen(req) as resp:
        return True

def main():
    print("=== REGISTRANDO PROFESORES CON SERVICE ROLE KEY ===")
    existing_users = get_existing_auth_users()
    print(f"Usuarios existentes en Auth: {len(existing_users)}\n")

    results = []

    for email, full_name in TEACHERS:
        clean_email = email.strip().lower()
        pwd = generate_8char_password()

        user_id = create_or_update_auth_user(existing_users, clean_email, full_name, pwd)
        upsert_profile(user_id, clean_email, full_name, pwd)

        print(f"  [OK] {full_name:<25} | {clean_email:<30} | ID: {user_id} | Clave: {pwd}")
        results.append({
            'name': full_name,
            'email': clean_email,
            'password': pwd,
            'id': user_id,
        })

    # Also include pluthornio in summary
    results.append({
        'name': 'Profesor de Prueba',
        'email': 'pluthornio@gmail.com',
        'password': 'Plut.2026',
        'id': '26c63323-3ea0-42d6-9ca0-0fed20c5d5da',
    })

    print("\n\n" + "=" * 80)
    print("=== TABLA DE CREDENCIALES OFICIALES (PROFESORES) ===")
    print("=" * 80)
    print(f"| {'Docente':<26} | {'Correo Electrónico':<32} | {'Contraseña':<12} |")
    print(f"|{'-'*28}|{'-'*34}|{'-'*14}|")
    for r in results:
        print(f"| {r['name']:<26} | {r['email']:<32} | {r['password']:<12} |")

if __name__ == '__main__':
    main()
