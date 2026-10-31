import pypdf
import glob
import os
import re

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

# Common particles for surnames
SURNAME_PREFIXES = {'DE', 'DEL', 'DE LA', 'DE LOS', 'SAN', 'SANTA', 'D', 'DA', 'DI', 'VON', 'VAN'}

def split_apellidos_nombres(raw_name):
    """
    Given raw 'Apellidos y Nombres' in Venezuelan format:
    Usually 2 surnames followed by given names.
    Handles compound surname particles like 'DE LA', 'DEL', 'D AVETA', etc.
    """
    tokens = raw_name.strip().split()
    if len(tokens) <= 2:
        return tokens[0], ' '.join(tokens[1:]) if len(tokens) > 1 else ''
    
    # Check if starts with D AVETA or DE LA or similar
    # Token 0 is D, Token 1 is AVETA -> surname is D AVETA + next surname
    i = 0
    surnames = []
    
    # First surname
    if tokens[i].upper() in ('D', 'DE') and i + 1 < len(tokens):
        if tokens[i+1].upper() in ('LA', 'LOS', 'LAS') and i + 2 < len(tokens):
            surnames.append(f"{tokens[i]} {tokens[i+1]} {tokens[i+2]}")
            i += 3
        else:
            surnames.append(f"{tokens[i]} {tokens[i+1]}")
            i += 2
    elif tokens[i].upper() in ('DEL', 'SAN', 'SANTA') and i + 1 < len(tokens):
        surnames.append(f"{tokens[i]} {tokens[i+1]}")
        i += 2
    else:
        surnames.append(tokens[i])
        i += 1
        
    # Second surname (if still at least 2 tokens left for given names, or 1 token left)
    if i < len(tokens) - 1: # leave at least 1 token for given name
        if tokens[i].upper() in ('DE', 'DEL', 'SAN') and i + 1 < len(tokens) - 1:
            surnames.append(f"{tokens[i]} {tokens[i+1]}")
            i += 2
        else:
            surnames.append(tokens[i])
            i += 1
            
    last_name = ' '.join(surnames)
    first_name = ' '.join(tokens[i:])
    return last_name, first_name

all_students = []
for filename, (grade, section) in pdf_classroom_map.items():
    path = os.path.join('matriculas_pdf', filename)
    reader = pypdf.PdfReader(path)
    text = reader.pages[0].extract_text()
    lines = [l.strip() for l in text.split('\n') if l.strip()]
    for line in lines:
        m = re.match(r'^(\d+)\s+(\d+)\s+(.+)$', line)
        if m:
            list_num = int(m.group(1))
            cedula = m.group(2)
            raw_name = m.group(3).strip()
            last_name, first_name = split_apellidos_nombres(raw_name)
            all_students.append({
                'list_num': list_num,
                'cedula': cedula,
                'raw_name': raw_name,
                'last_name': last_name,
                'first_name': first_name,
                'grade': grade,
                'section': section,
            })

print(f"Total extracted: {len(all_students)}")
print("Sample split:")
for s in all_students[:15]:
    print(f"  [{s['cedula']}] {s['raw_name']} -> Apellidos: '{s['last_name']}' | Nombres: '{s['first_name']}'")
