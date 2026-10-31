# -*- coding: utf-8 -*-
"""
Registers all teachers in Supabase:
- Creates Supabase Auth users via /auth/v1/signup
- Upserts profile with role='profesor', phone='[FORCE_PWD_CHANGE][PWD:<password>]'
- Leaves classrooms unassigned (teacher_id=None)
"""

import os
import json
import random
import urllib.request
import datetime

SUPABASE_URL = 'https://mkhcmfjyowketdahadvt.supabase.co'
SUPABASE_KEY = 'sb_publishable_fmS5vAc6n1gspsDUhE7-1w_yqQPAfpf'
ADMIN_EMAIL = 'henderljunior@gmail.com'
ADMIN_PASS = ''

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
    ('pluthornio@gmail.com', 'Profesor de Prueba'),
]

def generate_8char_password():
    upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
    lower = 'abcdefghijkmnpqrstuvwxyz'
    digits = '23456789'
    specials = '.!@#*'
    all_chars = upper + lower + digits + specials

    # Guarantee at least 1 of each required category
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

def get_admin_jwt():
    auth_url = f'{SUPABASE_URL}/auth/v1/token?grant_type=password'
    payload = json.dumps({'email': ADMIN_EMAIL, 'password': ADMIN_PASS}).encode()
    req = urllib.request.Request(
        auth_url,
        data=payload,
        headers={'apikey': SUPABASE_KEY, 'Content-Type': 'application/json'}
    )
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read().decode())['access_token']

def signup_user(email, password, full_name):
    signup_url = f'{SUPABASE_URL}/auth/v1/signup'
    payload = json.dumps({
        'email': email.strip().lower(),
        'password': password,
        'data': {'full_name': full_name, 'role': 'profesor'}
    }).encode()
    req = urllib.request.Request(
        signup_url,
        data=payload,
        headers={'apikey': SUPABASE_KEY, 'Content-Type': 'application/json'}
    )
    try:
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode())
            return (data.get('user') or data).get('id')
    except Exception as e:
        err = str(e)
        if hasattr(e, 'read'):
            err += ' ' + e.read().decode('utf-8', errors='ignore')
        # If user already exists, we will retrieve id from profile or existing
        return None

def upsert_profile(jwt, user_id, email, full_name, password):
    url = f'{SUPABASE_URL}/rest/v1/profiles'
    headers = {
        'apikey': SUPABASE_KEY,
        'Authorization': f'Bearer {jwt}',
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

def get_existing_profile(jwt, email):
    url = f'{SUPABASE_URL}/rest/v1/profiles?email=eq.{email.strip().lower()}'
    headers = {'apikey': SUPABASE_KEY, 'Authorization': f'Bearer {jwt}'}
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req) as resp:
        rows = json.loads(resp.read().decode())
        return rows[0] if rows else None

def main():
    print("=== REGISTRO EN LOTE DE PROFESORES ===")
    jwt = get_admin_jwt()
    print("Autenticado con Supabase Admin.\n")

    results = []

    for email, full_name in TEACHERS:
        clean_email = email.strip().lower()
        pwd = generate_8char_password()
        
        # 1. Check if profile already exists
        existing_prof = get_existing_profile(jwt, clean_email)
        user_id = None
        if existing_prof:
            user_id = existing_prof['id']
            print(f"• {full_name} ({clean_email}): Ya existe en profiles (ID: {user_id})")
        else:
            # 2. Try signup
            user_id = signup_user(clean_email, pwd, full_name)
            if not user_id:
                # In case signup failed but user exists in auth, fallback query
                existing_prof2 = get_existing_profile(jwt, clean_email)
                if existing_prof2:
                    user_id = existing_prof2['id']
            print(f"• {full_name} ({clean_email}): Registrado en Supabase Auth (ID: {user_id})")

        if not user_id:
            # Use deterministic uuid or random if completely orphaned
            import uuid
            user_id = str(uuid.uuid4())
            print(f"  [AVISO] Generando ID para profile: {user_id}")

        # 3. Upsert profile with [FORCE_PWD_CHANGE][PWD:<password>]
        upsert_profile(jwt, user_id, clean_email, full_name, pwd)
        print(f"  -> Perfil guardado con clave: {pwd} (1er inicio activo)")

        results.append({
            'name': full_name,
            'email': clean_email,
            'password': pwd,
            'id': user_id,
        })

    print("\n=== RESUMEN DE CREDENCIALES CREADAS ===")
    print(f"{'Docente':<25} | {'Correo':<32} | {'Contraseña (8 chars)':<15}")
    print("-" * 80)
    for r in results:
        print(f"{r['name']:<25} | {r['email']:<32} | {r['password']:<15}")

if __name__ == '__main__':
    main()
