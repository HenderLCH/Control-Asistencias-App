# -*- coding: utf-8 -*-
"""
Loads all 448 students extracted from the 12 PDFs into Supabase.
"""
import glob
import os
import re
import json
import urllib.request
import datetime
import pypdf
from test_gender import classify_student_gender, split_apellidos_nombres

SUPABASE_URL = 'https://mkhcmfjyowketdahadvt.supabase.co'
SUPABASE_KEY = 'sb_publishable_fmS5vAc6n1gspsDUhE7-1w_yqQPAfpf'

ADMIN_EMAIL = 'henderljunior@gmail.com'
ADMIN_PASS = ''

pdf_classroom_map = {
    '1ergrado A.pdf': ('1er Grado', 'A'),
    '1ergrado B.pdf': ('1er Grado', 'B'),
    '2dogrado A.pdf': ('2do Grado', 'A'),
    '2dogrado B.pdf': ('2do Grado', 'B'),
    '3ergrado A.pdf': ('3er Grado', 'A'),
    '3ergrado B.pdf': ('3er Grado', 'B'),
    '4togrado A.pdf': ('4to Grado', 'A'),
    '4togrado B.pdf': ('4to Grado', 'B'),
    '5togrado A.pdf': ('5to Grado', 'A'),
    '5togrado B.pdf': ('5to Grado', 'B'),
    '6togrado A.pdf': ('6to Grado', 'A'),
    '6togrado B.pdf': ('6to Grado', 'B'),
}

def to_title_case(text):
    words = text.split()
    lower_particles = {'de', 'del', 'la', 'las', 'los', 'y'}
    res = []
    for i, w in enumerate(words):
        w_lower = w.lower()
        if i > 0 and w_lower in lower_particles:
            res.append(w_lower)
        else:
            res.append(w.capitalize())
    return ' '.join(res)

def get_auth_token():
    auth_url = f'{SUPABASE_URL}/auth/v1/token?grant_type=password'
    auth_headers = {'apikey': SUPABASE_KEY, 'Content-Type': 'application/json'}
    auth_payload = json.dumps({'email': ADMIN_EMAIL, 'password': ADMIN_PASS}).encode()
    req = urllib.request.Request(auth_url, data=auth_payload, headers=auth_headers)
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read().decode())['access_token']

def get_classrooms(jwt):
    headers = {'apikey': SUPABASE_KEY, 'Authorization': f'Bearer {jwt}'}
    req = urllib.request.Request(f'{SUPABASE_URL}/rest/v1/classrooms?select=*', headers=headers)
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read().decode())

def parse_classroom_students(filename, grade, section):
    path = os.path.join('matriculas_pdf', filename)
    reader = pypdf.PdfReader(path)
    text = reader.pages[0].extract_text()
    lines = [l.strip() for l in text.split('\n') if l.strip()]
    records = []
    for line in lines:
        m = re.match(r'^(\d+)\s+(\d+)\s+(.+)$', line)
        if m:
            list_num = int(m.group(1))
            cedula = m.group(2)
            raw_name = m.group(3).strip()
            last_name, first_name = split_apellidos_nombres(raw_name)
            gender = classify_student_gender(first_name)
            
            fn = to_title_case(first_name)
            ln = to_title_case(last_name)
            
            records.append({
                'list_num': list_num,
                'cedula': cedula,
                'first_name': fn,
                'last_name': ln,
                'gender': gender,
                'grade': grade,
                'section': section,
            })
    return records

def insert_batch(jwt, rows):
    url = f'{SUPABASE_URL}/rest/v1/students'
    headers = {
        'apikey': SUPABASE_KEY,
        'Authorization': f'Bearer {jwt}',
        'Content-Type': 'application/json',
        'Prefer': 'return=minimal'
    }
    
    # Try with gender first
    try:
        req = urllib.request.Request(url, data=json.dumps(rows).encode('utf-8'), headers=headers)
        with urllib.request.urlopen(req) as resp:
            return True
    except Exception as e:
        err_msg = str(e)
        if hasattr(e, 'read'):
            err_msg += ' ' + e.read().decode('utf-8', errors='ignore')
        
        # If gender column not found, remove gender and rely on photo_url
        if 'gender' in err_msg:
            rows_no_gender = []
            for r in rows:
                r_copy = dict(r)
                r_copy.pop('gender', None)
                rows_no_gender.append(r_copy)
            req = urllib.request.Request(url, data=json.dumps(rows_no_gender).encode('utf-8'), headers=headers)
            with urllib.request.urlopen(req) as resp:
                return True
        else:
            raise Exception(f"Batch insert error: {err_msg}")

def main():
    print("1. Authenticating with Supabase...")
    jwt = get_auth_token()
    print("   Auth successful.")

    print("2. Fetching classrooms...")
    classrooms = get_classrooms(jwt)
    print(f"   Found {len(classrooms)} classrooms in DB.")

    classroom_map = {}
    for c in classrooms:
        key = (c.get('grade', '').strip(), c.get('section', '').strip())
        classroom_map[key] = c['id']

    # Delete existing test students first
    print("3. Checking existing students...")
    req_existing = urllib.request.Request(
        f'{SUPABASE_URL}/rest/v1/students?select=id',
        headers={'apikey': SUPABASE_KEY, 'Authorization': f'Bearer {jwt}'}
    )
    with urllib.request.urlopen(req_existing) as r:
        existing = json.loads(r.read().decode())
        print(f"   Existing students count: {len(existing)}")
        if existing:
            print("   Cleaning existing test student(s)...")
            req_del = urllib.request.Request(
                f'{SUPABASE_URL}/rest/v1/students?id=neq.00000000-0000-0000-0000-000000000000',
                headers={'apikey': SUPABASE_KEY, 'Authorization': f'Bearer {jwt}'},
                method='DELETE'
            )
            urllib.request.urlopen(req_del)
            print("   Cleaned.")

    print("4. Parsing PDFs and uploading classroom by classroom...")
    now_iso = datetime.datetime.now(datetime.timezone.utc).isoformat()
    total_inserted = 0

    for filename, (grade, section) in pdf_classroom_map.items():
        c_id = classroom_map.get((grade, section))
        if not c_id:
            print(f"   WARNING: Classroom not found for {grade} {section}!")
            continue

        st_list = parse_classroom_students(filename, grade, section)
        rows_to_insert = []
        for s in st_list:
            rows_to_insert.append({
                'cedula': s['cedula'],
                'first_name': s['first_name'],
                'last_name': s['last_name'],
                'gender': s['gender'],
                'classroom_id': c_id,
                'grade': grade,
                'section': section,
                'photo_url': f"gender:{s['gender']}",
                'is_active': True,
                'created_at': now_iso,
            })

        insert_batch(jwt, rows_to_insert)
        v_count = sum(1 for s in st_list if s['gender'] == 'M')
        h_count = sum(1 for s in st_list if s['gender'] == 'F')
        total_inserted += len(rows_to_insert)
        print(f"   [OK] {grade} {section:1s}: {len(rows_to_insert):2d} estudiantes cargados ({v_count} V / {h_count} H)")

    print(f"\n¡EXITO TOTAL! Se han insertado {total_inserted} estudiantes en la base de datos de Supabase.")

if __name__ == '__main__':
    main()
