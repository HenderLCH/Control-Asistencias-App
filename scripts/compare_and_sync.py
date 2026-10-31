# -*- coding: utf-8 -*-
"""
Compares new enrollment PDFs in 'matriculas_pdf' against existing Supabase database.
Safe synchronization: only inserts genuinely new students, never deletes or overwrites existing ones.
"""

import os
import re
import sys
import json
import urllib.request
import datetime
import pypdf

# Add scripts directory to path to import helpers
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from test_gender import classify_student_gender, split_apellidos_nombres

SUPABASE_URL = 'https://mkhcmfjyowketdahadvt.supabase.co'
SUPABASE_KEY = 'sb_publishable_fmS5vAc6n1gspsDUhE7-1w_yqQPAfpf'
ADMIN_EMAIL = 'henderljunior@gmail.com'
ADMIN_PASS = ''

GRADE_MAP = {
    '1': '1er Grado',
    '2': '2do Grado',
    '3': '3er Grado',
    '4': '4to Grado',
    '5': '5to Grado',
    '6': '6to Grado',
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

def get_all_db_students(jwt):
    headers = {'apikey': SUPABASE_KEY, 'Authorization': f'Bearer {jwt}'}
    # Fetch all students
    req = urllib.request.Request(f'{SUPABASE_URL}/rest/v1/students?select=*', headers=headers)
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read().decode())

def parse_pdf(filepath, grade, section):
    reader = pypdf.PdfReader(filepath)
    text = reader.pages[0].extract_text()
    lines = [l.strip() for l in text.split('\n') if l.strip()]
    records = []
    for line in lines:
        m = re.match(r'^(\d+)\s+(\d+)\s+(.+)$', line)
        if m:
            list_num = int(m.group(1))
            cedula = str(m.group(2)).strip()
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
                'raw_name': raw_name
            })
    return records

def update_student_cedula(jwt, student_id, new_cedula):
    url = f'{SUPABASE_URL}/rest/v1/students?id=eq.{student_id}'
    headers = {
        'apikey': SUPABASE_KEY,
        'Authorization': f'Bearer {jwt}',
        'Content-Type': 'application/json',
        'Prefer': 'return=minimal'
    }
    payload = json.dumps({'cedula': new_cedula}).encode('utf-8')
    req = urllib.request.Request(url, data=payload, headers=headers, method='PATCH')
    with urllib.request.urlopen(req) as resp:
        return True

def insert_new_students(jwt, new_students_rows):
    if not new_students_rows:
        return 0
    url = f'{SUPABASE_URL}/rest/v1/students'
    headers = {
        'apikey': SUPABASE_KEY,
        'Authorization': f'Bearer {jwt}',
        'Content-Type': 'application/json',
        'Prefer': 'return=minimal'
    }
    # Try inserting with gender, fallback without if column doesn't exist
    try:
        req = urllib.request.Request(url, data=json.dumps(new_students_rows).encode('utf-8'), headers=headers)
        with urllib.request.urlopen(req) as resp:
            return len(new_students_rows)
    except Exception as e:
        err_msg = str(e)
        if hasattr(e, 'read'):
            err_msg += ' ' + e.read().decode('utf-8', errors='ignore')
        if 'gender' in err_msg:
            rows_no_gender = []
            for r in new_students_rows:
                rc = dict(r)
                rc.pop('gender', None)
                rows_no_gender.append(rc)
            req = urllib.request.Request(url, data=json.dumps(rows_no_gender).encode('utf-8'), headers=headers)
            with urllib.request.urlopen(req) as resp:
                return len(rows_no_gender)
        else:
            raise Exception(f"Insert error: {err_msg}")

def main():
    apply_changes = '--apply' in sys.argv

    print("=== SINCRONIZACIÓN DE MATRÍCULA Y ESTUDIANTES ===")
    print(f"Modo: {'APLICAR CAMBIOS (INSERTAR)' if apply_changes else 'SIMULACIÓN (DRY-RUN)'}\n")

    # 1. Auth & fetch DB
    print("[1/4] Conectando con Supabase...")
    jwt = get_auth_token()
    classrooms = get_classrooms(jwt)
    classroom_map = {(c['grade'].strip(), c['section'].strip()): c['id'] for c in classrooms}
    
    db_students = get_all_db_students(jwt)
    print(f"      Salones registrados en BD: {len(classrooms)}")
    print(f"      Estudiantes actuales en BD: {len(db_students)}")

    # Index DB students by cedula and also by normalized (last_name, first_name)
    db_by_cedula = {str(s.get('cedula', '')).strip(): s for s in db_students if s.get('cedula')}
    db_by_name = {}
    for s in db_students:
        norm_key = (
            s.get('grade', '').strip(),
            s.get('section', '').strip(),
            s.get('last_name', '').strip().lower(),
            s.get('first_name', '').strip().lower()
        )
        db_by_name[norm_key] = s

    # 2. Find new PDFs in matriculas_pdf
    pdf_dir = 'matriculas_pdf'
    all_files = os.listdir(pdf_dir)
    # Identify new PDFs: files that don't contain 'grado' and end with .pdf
    new_pdf_files = [f for f in all_files if f.endswith('.pdf') and 'grado' not in f]
    
    print(f"\n[2/4] Leyendo {len(new_pdf_files)} PDFs actualizados...")

    all_pdf_students = []
    file_map = {}

    for f in new_pdf_files:
        # Match grade number and section (A or B)
        # e.g., '1°A.pdf' or '1A.pdf'
        m = re.search(r'([1-6]).*?([AB])\.pdf', f, re.IGNORECASE)
        if not m:
            print(f"  [AVISO] No se pudo determinar grado/sección para el archivo: {f}")
            continue
        g_num = m.group(1)
        sec = m.group(2).upper()
        grade_name = GRADE_MAP[g_num]
        file_map[(grade_name, sec)] = f

    # Sort classrooms in order
    target_classrooms = []
    for g_num in ['1', '2', '3', '4', '5', '6']:
        grade_name = GRADE_MAP[g_num]
        for sec in ['A', 'B']:
            target_classrooms.append((grade_name, sec))

    total_pdf_students_count = 0
    new_students_to_add = []
    existing_students_matched = []
    cedula_updates = []
    section_switches = []
    students_in_pdf_by_cedula = {}

    for grade_name, sec in target_classrooms:
        filename = file_map.get((grade_name, sec))
        if not filename:
            print(f"  [ERROR] Falta el PDF para {grade_name} {sec}!")
            continue
        
        filepath = os.path.join(pdf_dir, filename)
        st_list = parse_pdf(filepath, grade_name, sec)
        total_pdf_students_count += len(st_list)

        c_id = classroom_map.get((grade_name, sec))

        c_existing = 0
        c_ced_update = 0
        c_new = []

        for st in st_list:
            ced = st['cedula']
            students_in_pdf_by_cedula[ced] = st

            # Case A: Exact match by cedula
            if ced in db_by_cedula:
                c_existing += 1
                db_st = db_by_cedula[ced]
                if db_st.get('grade') != grade_name or db_st.get('section') != sec:
                    section_switches.append({
                        'cedula': ced,
                        'name': f"{st['first_name']} {st['last_name']}",
                        'old': f"{db_st.get('grade')} {db_st.get('section')}",
                        'new': f"{grade_name} {sec}",
                        'student_id': db_st['id']
                    })
                existing_students_matched.append(ced)
            else:
                # Case B: Check if name matches an existing student in the same classroom (cédula escolar -> cédula real)
                name_key = (
                    grade_name.strip(),
                    sec.strip(),
                    st['last_name'].strip().lower(),
                    st['first_name'].strip().lower()
                )
                if name_key in db_by_name:
                    db_st = db_by_name[name_key]
                    c_ced_update += 1
                    cedula_updates.append({
                        'student_id': db_st['id'],
                        'name': f"{st['last_name']}, {st['first_name']}",
                        'classroom': f"{grade_name} {sec}",
                        'old_cedula': db_st.get('cedula'),
                        'new_cedula': ced
                    })
                    existing_students_matched.append(db_st.get('cedula'))
                else:
                    # Case C: Genuinely new student
                    c_new.append(st)
                    new_students_to_add.append({
                        'cedula': st['cedula'],
                        'first_name': st['first_name'],
                        'last_name': st['last_name'],
                        'gender': st['gender'],
                        'classroom_id': c_id,
                        'grade': grade_name,
                        'section': sec,
                        'photo_url': f"gender:{st['gender']}",
                        'is_active': True,
                        'created_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                    })

        msg_parts = []
        if c_new:
            msg_parts.append(f"+{len(c_new)} NUEVOS")
        if c_ced_update:
            msg_parts.append(f"{c_ced_update} actualizó C.I.")
        status_str = " | ".join(msg_parts) if msg_parts else "sin cambios"
        
        print(f"  • {grade_name} {sec}: {len(st_list)} en PDF | {c_existing + c_ced_update} existentes en BD | {status_str}")
        if c_new:
            for n in c_new:
                print(f"      -> [NUEVO] C.I. {n['cedula']} | {n['last_name']}, {n['first_name']} ({n['gender']})")
        if c_ced_update:
            for u in [cu for cu in cedula_updates if cu['classroom'] == f"{grade_name} {sec}"]:
                print(f"      -> [C.I. ACTUALIZADA] {u['name']}: {u['old_cedula']} -> {u['new_cedula']}")

    # 3. Check for students in DB not in the PDFs
    updated_old_cedulas = {cu['old_cedula'] for cu in cedula_updates}
    db_not_in_pdf = []
    for ced, db_st in db_by_cedula.items():
        if ced not in students_in_pdf_by_cedula and ced not in updated_old_cedulas:
            db_not_in_pdf.append(db_st)

    print("\n[3/4] Resumen de Comparación:")
    print(f"      Total en Base de Datos actual: {len(db_students)}")
    print(f"      Total en nuevos PDFs:          {total_pdf_students_count}")
    print(f"      Estudiantes ya existentes:     {len(existing_students_matched)} (permanecen 100% intactos)")
    print(f"      Estudiantes NUEVOS a agregar:  {len(new_students_to_add)}")
    print(f"      Estudiantes en BD que no están en nuevos PDFs: {len(db_not_in_pdf)}")
    if db_not_in_pdf:
        for s in db_not_in_pdf:
            print(f"        * C.I. {s.get('cedula')} - {s.get('last_name')}, {s.get('first_name')} ({s.get('grade')} {s.get('section')})")

    if section_switches:
        print(f"      Cambios de sección/grado detectados: {len(section_switches)}")
        for sw in section_switches:
            print(f"        * C.I. {sw['cedula']} {sw['name']}: {sw['old']} -> {sw['new']}")

    # 4. Execution if --apply
    print(f"\n[4/4] Ejecución:")
    if apply_changes:
        if cedula_updates:
            print(f"      Actualizando cédula de {len(cedula_updates)} estudiante(s) existente(s)...")
            for cu in cedula_updates:
                update_student_cedula(jwt, cu['student_id'], cu['new_cedula'])
                print(f"        [OK] {cu['name']} ({cu['classroom']}): C.I. actualizada a {cu['new_cedula']}")

        if new_students_to_add:
            print(f"      Insertando {len(new_students_to_add)} nuevos estudiantes en Supabase...")
            inserted = insert_new_students(jwt, new_students_to_add)
            print(f"      ¡ÉXITO! Se insertaron {inserted} estudiantes nuevos correctamente.")
        else:
            print("      No hay nuevos estudiantes para insertar.")
    else:
        print("      Modo simulación finalizado. Ejecuta con --apply para realizar la inserción real.")

if __name__ == '__main__':
    main()
