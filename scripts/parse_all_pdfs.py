import pypdf
import glob
import os
import re

files = sorted(glob.glob('matriculas_pdf/*.pdf'))

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

total_parsed = 0
for filename, (grade, section) in pdf_classroom_map.items():
    path = os.path.join('matriculas_pdf', filename)
    reader = pypdf.PdfReader(path)
    text = reader.pages[0].extract_text()
    lines = [l.strip() for l in text.split('\n') if l.strip()]
    
    student_lines = []
    for line in lines:
        # Match pattern: number + space + identifier (digits) + space + name
        m = re.match(r'^(\d+)\s+(\d+)\s+(.+)$', line)
        if m:
            student_lines.append((int(m.group(1)), m.group(2), m.group(3).strip()))
    
    print(f"{grade} {section} ({filename}): {len(student_lines)} students (Max list num: {student_lines[-1][0] if student_lines else 0})")
    total_parsed += len(student_lines)

print(f"\nTotal students across all 12 classrooms: {total_parsed}")
