import json
import urllib.request

SUPABASE_URL = 'https://mkhcmfjyowketdahadvt.supabase.co'
SUPABASE_KEY = 'sb_publishable_fmS5vAc6n1gspsDUhE7-1w_yqQPAfpf'

ADMIN_EMAIL = 'henderljunior@gmail.com'
ADMIN_PASS = ''

def get_auth_token_and_user():
    auth_url = f'{SUPABASE_URL}/auth/v1/token?grant_type=password'
    auth_headers = {'apikey': SUPABASE_KEY, 'Content-Type': 'application/json'}
    auth_payload = json.dumps({'email': ADMIN_EMAIL, 'password': ADMIN_PASS}).encode()
    req = urllib.request.Request(auth_url, data=auth_payload, headers=auth_headers)
    with urllib.request.urlopen(req) as r:
        data = json.loads(r.read().decode())
        return data['access_token'], data['user']['id']

jwt, user_id = get_auth_token_and_user()
print(f"Logged in user ID: {user_id}")
headers = {
    'apikey': SUPABASE_KEY,
    'Authorization': f'Bearer {jwt}',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation'
}

# 1. Fetch 2 students from 1er Grado Sección A
req = urllib.request.Request(f'{SUPABASE_URL}/rest/v1/students?select=id,first_name,last_name,classroom_id&limit=2', headers=headers)
with urllib.request.urlopen(req) as resp:
    students = json.loads(resp.read().decode())

print(f"Estudiantes seleccionados para la prueba:")
s1 = students[0]
s2 = students[1]
print(f"Estudiante 1 (2 tardanzas - Alerta Preventiva): {s1['first_name']} {s1['last_name']} (ID: {s1['id']})")
print(f"Estudiante 2 (3 tardanzas - Citar Representante): {s2['first_name']} {s2['last_name']} (ID: {s2['id']})")

# Primero limpiamos cualquier asistencia previa de prueba para estos 2 estudiantes en esas fechas
for s in [s1, s2]:
    del_req = urllib.request.Request(
        f"{SUPABASE_URL}/rest/v1/attendance?student_id=eq.{s['id']}",
        headers=headers,
        method='DELETE'
    )
    try:
        with urllib.request.urlopen(del_req) as resp:
            pass
    except Exception as e:
        print(f"Notice during delete: {e}")

# Insertar 2 tardanzas para Estudiante 1
records_s1 = [
    {
        'student_id': s1['id'],
        'classroom_id': s1['classroom_id'],
        'date': '2026-09-22',
        'status': 'tardanza',
        'notes': 'Llegó 15 minutos tarde',
        'marked_by_id': user_id
    },
    {
        'student_id': s1['id'],
        'classroom_id': s1['classroom_id'],
        'date': '2026-09-23',
        'status': 'tardanza',
        'notes': 'Llegó 20 minutos tarde (2da tardanza)',
        'marked_by_id': user_id
    }
]

# Insertar 3 tardanzas para Estudiante 2
records_s2 = [
    {
        'student_id': s2['id'],
        'classroom_id': s2['classroom_id'],
        'date': '2026-09-22',
        'status': 'tardanza',
        'notes': 'Llegó tarde - 1ra',
        'marked_by_id': user_id
    },
    {
        'student_id': s2['id'],
        'classroom_id': s2['classroom_id'],
        'date': '2026-09-23',
        'status': 'tardanza',
        'notes': 'Llegó tarde - 2da',
        'marked_by_id': user_id
    },
    {
        'student_id': s2['id'],
        'classroom_id': s2['classroom_id'],
        'date': '2026-09-24',
        'status': 'tardanza',
        'notes': 'Llegó tarde - 3ra (Acumuló 3 tardanzas -> Citar Representante)',
        'marked_by_id': user_id
    }
]

all_records = records_s1 + records_s2
insert_req = urllib.request.Request(
    f"{SUPABASE_URL}/rest/v1/attendance",
    data=json.dumps(all_records).encode('utf-8'),
    headers=headers,
    method='POST'
)

with urllib.request.urlopen(insert_req) as resp:
    inserted = json.loads(resp.read().decode())
    print(f"¡Éxito! Se insertaron {len(inserted)} registros de tardanza en Supabase.")
