# -*- coding: utf-8 -*-
"""
Script to create teacher user accounts in Supabase with 8-character secure passwords,
without assigned classrooms, and marked with [FORCE_PWD_CHANGE] so they are required
to change their password on first login.
"""

import sys
import os
import json
import random
import string
import urllib.request
import datetime

SUPABASE_URL = 'https://mkhcmfjyowketdahadvt.supabase.co'
SUPABASE_KEY = 'sb_publishable_fmS5vAc6n1gspsDUhE7-1w_yqQPAfpf'
ADMIN_EMAIL = 'henderljunior@gmail.com'
ADMIN_PASS = ''

def generate_8char_password():
    """Generates an 8-character password with upper, lower, digit, and special char (.)"""
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

def create_teacher_account(email, full_name, initial_password=None):
    if not initial_password:
        initial_password = generate_8char_password()

    # 1. Sign up user via Supabase Auth signup endpoint
    signup_url = f'{SUPABASE_URL}/auth/v1/signup'
    signup_payload = json.dumps({
        'email': email.strip().lower(),
        'password': initial_password,
        'data': {
            'full_name': full_name.strip(),
            'role': 'profesor',
        }
    }).encode()
    signup_req = urllib.request.Request(
        signup_url,
        data=signup_payload,
        headers={'apikey': SUPABASE_KEY, 'Content-Type': 'application/json'}
    )

    user_id = None
    try:
        with urllib.request.urlopen(signup_req) as resp:
            resp_data = json.loads(resp.read().decode())
            user_id = resp_data.get('id') or resp_data.get('user', {}).get('id')
    except Exception as e:
        err_msg = str(e)
        if hasattr(e, 'read'):
            err_msg += ' ' + e.read().decode('utf-8', errors='ignore')
        # Check if already registered
        if 'User already registered' in err_msg or 'already exists' in err_msg:
            print(f"  [AVISO] El correo {email} ya se encuentra registrado.")
            return None
        raise Exception(f"Error registrando en Supabase Auth: {err_msg}")

    # 2. Authenticate admin to update profile with [FORCE_PWD_CHANGE] and role
    jwt = get_admin_jwt()
    if user_id:
        profile_url = f'{SUPABASE_URL}/rest/v1/profiles?id=eq.{user_id}'
        profile_payload = json.dumps({
            'id': user_id,
            'email': email.strip().lower(),
            'full_name': full_name.strip(),
            'role': 'profesor',
            'phone': f'[FORCE_PWD_CHANGE][TEMP_PWD:{initial_password}]',
            'is_active': True,
            'updated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        }).encode()
        pref_headers = {
            'apikey': SUPABASE_KEY,
            'Authorization': f'Bearer {jwt}',
            'Content-Type': 'application/json',
            'Prefer': 'resolution=merge-duplicates'
        }
        upsert_req = urllib.request.Request(
            f'{SUPABASE_URL}/rest/v1/profiles',
            data=profile_payload,
            headers=pref_headers
        )
        try:
            with urllib.request.urlopen(upsert_req) as resp:
                pass
        except Exception as e:
            print(f"  [ERROR] Actualizando perfil: {e}")

    return {
        'id': user_id,
        'email': email,
        'full_name': full_name,
        'password': initial_password,
    }

if __name__ == '__main__':
    print("Módulo de creación de profesores listo.")
