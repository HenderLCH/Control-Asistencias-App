import json
import urllib.request
import pypdf
import glob
import os
import re

SUPABASE_URL = 'https://mkhcmfjyowketdahadvt.supabase.co'
SUPABASE_KEY = 'sb_publishable_fmS5vAc6n1gspsDUhE7-1w_yqQPAfpf'

headers = {
    'apikey': SUPABASE_KEY,
    'Authorization': f'Bearer {SUPABASE_KEY}',
    'Content-Type': 'application/json'
}

def get_classrooms():
    req = urllib.request.Request(f'{SUPABASE_URL}/rest/v1/classrooms?select=*', headers=headers)
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read().decode())

def get_existing_students():
    req = urllib.request.Request(f'{SUPABASE_URL}/rest/v1/students?select=id,cedula,first_name,last_name,classroom_id', headers=headers)
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read().decode())

if __name__ == '__main__':
    classrooms = get_classrooms()
    print(f'Total classrooms in DB: {len(classrooms)}')
    for c in classrooms:
        print(f"ID: {c['id']} | Grade: {c.get('grade')} | Section: {c.get('section')} | Display: {c.get('display_name') or c.get('name')}")

    students = get_existing_students()
    print(f'Total students in DB currently: {len(students)}')
