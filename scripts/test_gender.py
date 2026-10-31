# -*- coding: utf-8 -*-
import glob
import os
import re
import json
import pypdf

# Comprehensive dictionary
FEMALE_EXTRA = {
    'NICOLL', 'MONSERRAT', 'MONTSERRAT', 'ESLYN', 'ALEXA', 'LEAD', 'MICHELL', 'MICHELLE',
    'HYRANNY', 'JULIANNA', 'ANHELYS', 'NATHALY', 'KAYLANA', 'AYLET', 'KAROL', 'JULIETH',
    'LYMSAI', 'ORIANNY', 'JHANMARY', 'SOFHIA', 'ALVRANNY', 'SAHIELA', 'BRIANNY', 'SARAI',
    'ALANI', 'KETZALI', 'OSMAIREL', 'EURIMAR', 'JADE', 'MAHOLY', 'NICOL', 'ANDREINA',
    'EYLIN', 'ESTEFFANIA', 'CRISTAL', 'DAYLIN', 'ROSMERY', 'NAILET', 'GLENDY', 'SARAY',
    'MARLIN', 'ANTONELA', 'ABRYL', 'LORIEL', 'GISELLE', 'TALIANA', 'JAHILEN', 'GIANELLA',
    'GISSELLE', 'ALESSANDRA', 'KLEEYNI', 'AINHOA', 'ALESSIA', 'MARIE', 'GIALLIANNI',
    'PAULINA', 'DAHIANA', 'NIKITA', 'BRYANA', 'LINETH', 'MARIAVICTORIA', 'ALAIA', 'SARAHI',
    'JANA', 'SALETTE', 'ANALICIA', 'AYSEL', 'AINARA', 'ROSELYN', 'NATHALIA', 'ANGELA',
    'ISABELA', 'SAARETH', 'PAMELA', 'ORIANA', 'DENNIRE', 'BRYANNA', 'ESMERALDA', 'KARLA',
    'SARAITH', 'ALEGNA', 'DAYNIMAR', 'AITHANA', 'NICOLE', 'MIA', 'EVA', 'ABBY', 'LUNA',
    'VERONICA', 'SALOME', 'SALOMÉ', 'JIMENA', 'EMMA', 'LUCIANA', 'ZOE', 'ALMALY', 'ALISON',
    'ARANZA', 'ANYELI', 'ANTHONELA', 'ANTONELLA', 'CATALINA', 'MIRANDA', 'PAULA', 'ROSANGEL',
    'AMANDA', 'GABRIELA', 'MARIA', 'MARÍA', 'WALESKA', 'EVOLET', 'SARAH', 'SARA', 'ARANZZA',
    'VALERY', 'DAYNNA', 'NATALIA', 'VALENTINA', 'ANTHONELLA', 'FIORELLA', 'ISABELLA', 'ROMINA',
    'SOFIA', 'SOFÍA', 'ANAHI', 'ANAHÍ', 'DAILIANY', 'YULIETH', 'DAIAN', 'CHARLOTTE', 'NOELIA',
    'SOPHIA', 'LUCIA', 'LUCÍA', 'ISAMAR', 'FERNANDA', 'ANGELICA', 'ANGÉLICA', 'CAROLINA',
    'ALEXANDRA', 'SAMARA', 'JOHANNA', 'MAIA', 'ALEJANDRA', 'VICTORIA', 'CAMILA', 'SAMANTHA',
    'MARIANA', 'DANIELA', 'VALERIA', 'FABIANA', 'STEPHANIE', 'ESTEFANIA', 'ESTEFANÍA',
    'BARBARA', 'BÁRBARA', 'PAOLA', 'ANDREA', 'ADRIANA', 'CLAUDIA', 'JULIA', 'JULIANA',
    'PATRICIA', 'CARMEN', 'ANA', 'ELIZABETH', 'GENESIS', 'GÉNESIS', 'GABRIELLE', 'ISABEL',
    'BEATRIZ', 'RAQUEL', 'MELANIE', 'ASHLEY', 'EMILY', 'BRIANNA', 'SHANTAL', 'IVANNA',
    'AURA', 'IRENE', 'MONICA', 'MÓNICA', 'SILVIA', 'ELENA', 'TERESA', 'ROSA', 'INÉS',
    'INES', 'LUISA', 'AITANA', 'ALONDRA', 'AMPARO', 'ANABELLA', 'ANASTASIA', 'ANGELES',
    'ÁNGELES', 'ANTONIA', 'ARANTZA', 'AURORA', 'BELEN', 'BELÉN', 'BIANCA', 'CAMILLE',
    'CANDELA', 'CARLA', 'CARLOTTA', 'CECILIA', 'CELESTE', 'CORINA', 'CRISTINA', 'DAFNE',
    'DAIANA', 'DANNA', 'DELFINA', 'DIANA', 'DOLORES', 'DOMINICA', 'ELIANA', 'ELISA',
    'FATIMA', 'FÁTIMA', 'FRANCESCA', 'GUADALUPE', 'HELENA', 'IGNACIA', 'ISIDORA', 'JAZMIN',
    'JAZMÍN', 'JOSEFINA', 'JUANA', 'JULIETA', 'LARA', 'LAURA', 'LIA', 'LÍA', 'LILIANA',
    'LOLA', 'LORENA', 'LOURDES', 'LUCERO', 'LUDMILA', 'MACARENA', 'MAGDALENA', 'MANUELA',
    'MARA', 'MARCELA', 'MARGARITA', 'MARINA', 'MARTINA', 'MERCEDES', 'MICAELA', 'MILAGROS',
    'MORENA', 'NADIA', 'NAHOMI', 'NAOMI', 'NEREA', 'NOEMI', 'NOEMÍ', 'NURIA', 'OLIVIA',
    'PALOMA', 'PILAR', 'REBECA', 'REGINA', 'RENATA', 'ROCIO', 'ROCÍO', 'ROSALIA', 'ROSALÍA',
    'ROSARIO', 'RUTH', 'SABRINA', 'SUSANA', 'TAMARA', 'TATIANA', 'TRINIDAD', 'URSULA',
    'ÚRSULA', 'VALENTINE', 'VERA', 'VIOLETA', 'VIRGINIA', 'XIMENA', 'YASMIN', 'YAZMIN',
    'ZULAY', 'MARIANNY', 'YORGELIS', 'YULIANNY', 'DAHIANNA', 'FRANSHESCA', 'GRECIA',
    'ISADORA', 'JOHANA', 'KALETH', 'LESLIE', 'MAYRA', 'NAYELIS', 'ORIANGEL', 'SCARLET',
    'YENIFER', 'YULIET', 'ZAHIRA', 'ZORAIDA', 'ANAHYS', 'ANMARY', 'DILARY', 'FABIOLA',
    'GIANNA', 'HILARY', 'KATHERINE', 'LEANDRA', 'MAILEN', 'NAYRETH', 'OSMARY', 'ROXANA',
    'SHANTALL', 'YOSELIN', 'ZULMAR'
}

MALE_EXTRA = {
    'DYLAN', 'SEBASTIAN', 'SEBASTIÁN', 'ANTONIO', 'MARIANO', 'GAEL', 'JOSHUA', 'KAEL',
    'JHOSMAR', 'HARRYSON', 'ANDRES', 'ANDRÉS', 'MIGUEL', 'MADINSSON', 'ISAAC', 'MATEO',
    'LEONARDO', 'DANIELL', 'ANGEL', 'ÁNGEL', 'LUCAS', 'SANTIAGO', 'VICTOR', 'VÍCTOR',
    'JUAN', 'PAUL', 'JEREMY', 'JESUS', 'JESÚS', 'SAMUEL', 'MILAN', 'MATHEO', 'JOHAN',
    'ALEJANDRO', 'JOSUE', 'JOSUÉ', 'STEFANO', 'KALET', 'DANIEL', 'SAID', 'CÁSTOR', 'CASTOR',
    'XAVID', 'GABRIEL', 'ALEXANDER', 'OMAR', 'CAMILO', 'JOSE', 'JOSÉ', 'IGNACIO', 'EMMANUEL',
    'CARLOS', 'DAVID', 'FERNANDO', 'FABIAN', 'FABIÁN', 'JOSUHÉ', 'JOSUHE', 'LUIS', 'MANUEL',
    'ADRIAN', 'ADRIÁN', 'ALONSO', 'ALVARO', 'ÁLVARO', 'BENJAMIN', 'BENJAMÍN', 'BRUNO',
    'CRISTOBAL', 'CRISTÓBAL', 'DIEGO', 'EDUARDO', 'ELIAS', 'ELÍAS', 'EMILIANO', 'ENRIQUE',
    'ESTEBAN', 'FELIPE', 'FRANCISCO', 'GASPAR', 'GONZALO', 'GUILLERMO', 'GUSTAVO', 'HECTOR',
    'HÉCTOR', 'HUGO', 'IAN', 'ISMAEL', 'IVAN', 'IVÁN', 'JAVIER', 'JERONIMO',
    'JERÓNIMO', 'JOAQUIN', 'JOAQUÍN', 'JORGE', 'JULIAN', 'JULIÁN', 'LEON', 'LEÓN', 'LORENZO',
    'LUCIANO', 'MARCOS', 'MARIO', 'MARTIN', 'MARTÍN', 'MATIAS', 'MATÍAS', 'MAURICIO',
    'MAXIMO', 'MÁXIMO', 'NICOLAS', 'NICOLÁS', 'PABLO', 'PATRICIO', 'PEDRO', 'RAFAEL',
    'RAMIRO', 'RODRIGO', 'SALVADOR', 'SIMON', 'SIMÓN', 'TOMAS', 'TOMÁS', 'VALENTIN',
    'VALENTÍN', 'VICENTE', 'ALFREDO', 'ALBERTO', 'ALDAIR', 'ALEXIS', 'ALONZO', 'ANGELO',
    'ÁNGELO', 'ARNALDO', 'AXEL', 'BLAS', 'CESAR', 'CÉSAR', 'CRISTIAN', 'DARIO', 'DARÍO',
    'DOMINGO', 'EDGAR', 'EDWARD', 'ERICK', 'ERNESTO', 'EZEQUIEL', 'FABRICIO', 'FRANCO',
    'GERARDO', 'GIOVANNI', 'ISAIAS', 'ISAÍAS', 'JAIRO', 'JEAN', 'JHON', 'JHONATAN',
    'JONATHAN', 'JULIO', 'KENNETH', 'LEANDRO', 'LIAM', 'MARCELO', 'MAX', 'MAXIMILIANO',
    'MOISES', 'MOISÉS', 'NELSON', 'NESTOR', 'NÉSTOR', 'OCTAVIO', 'OLIVER', 'ORLANDO',
    'OSCAR', 'ÓSCAR', 'OSWALDO', 'RAMON', 'RAMÓN', 'RAUL', 'RAÚL', 'REINALDO', 'RENATO',
    'RICARDO', 'ROBERTO', 'RODOLFO', 'RUBEN', 'RUBÉN', 'SERGIO', 'THEO', 'THIAGO',
    'VALENTINO', 'WILMER', 'YAHIR', 'YEIKER', 'YONAIDEL', 'DAEL', 'ABRAHAM', 'ELAN',
    'ÉLAN', 'HASSAN', 'AGUSTÍN', 'AGUSTIN', 'MYLAN', 'JESSED', 'DOMINIC', 'PAOLO',
    'KEIDER', 'JHOSUE', 'DENZEL', 'SMITH', 'KEYNNER', 'RONALDO', 'BRENYER', 'SAMAEL',
    'JHAZIEL', 'MATHIAS', 'ELI', 'IBRAHIM', 'ALÍ', 'ALI'
}

def classify_student_gender(first_name_str):
    tokens = [t.strip().upper() for t in first_name_str.split() if t.strip().upper() not in ('DE', 'DEL', 'LA', 'LOS', 'SAN')]
    
    # 1. Exact match on any token in male or female set
    # Priority to the first token
    if tokens:
        first = tokens[0]
        if first in FEMALE_EXTRA:
            return 'F'
        if first in MALE_EXTRA:
            return 'M'
            
    # Check other tokens
    for tok in tokens[1:]:
        if tok in FEMALE_EXTRA:
            return 'F'
        if tok in MALE_EXTRA:
            return 'M'
            
    # Fallback heuristics
    if tokens:
        first = tokens[0]
        if first.endswith(('A', 'IA', 'INA', 'ELLA', 'ETTE', 'ELA', 'IS', 'ETH', 'Y')):
            return 'F'
    return 'M'

# Now test
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

def split_apellidos_nombres(raw_name):
    tokens = raw_name.strip().split()
    if len(tokens) <= 2:
        return tokens[0], ' '.join(tokens[1:]) if len(tokens) > 1 else ''
    i = 0
    surnames = []
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
        
    if i < len(tokens) - 1:
        if tokens[i].upper() in ('DE', 'DEL', 'SAN') and i + 1 < len(tokens) - 1:
            surnames.append(f"{tokens[i]} {tokens[i+1]}")
            i += 2
        else:
            surnames.append(tokens[i])
            i += 1
            
    last_name = ' '.join(surnames)
    first_name = ' '.join(tokens[i:])
    return last_name, first_name

results = {}
all_records = []

for filename, (grade, section) in pdf_classroom_map.items():
    path = os.path.join('matriculas_pdf', filename)
    reader = pypdf.PdfReader(path)
    text = reader.pages[0].extract_text()
    lines = [l.strip() for l in text.split('\n') if l.strip()]
    
    m_count = 0
    f_count = 0
    for line in lines:
        m = re.match(r'^(\d+)\s+(\d+)\s+(.+)$', line)
        if m:
            list_num = int(m.group(1))
            cedula = m.group(2)
            raw_name = m.group(3).strip()
            last_name, first_name = split_apellidos_nombres(raw_name)
            gender = classify_student_gender(first_name)
            if gender == 'M':
                m_count += 1
            else:
                f_count += 1
            all_records.append({
                'list_num': list_num,
                'cedula': cedula,
                'last_name': last_name,
                'first_name': first_name,
                'gender': gender,
                'grade': grade,
                'section': section,
            })
            
    results[f"{grade} {section}"] = (m_count, f_count, m_count + f_count)

print("Accurate Classroom V / H counts:")
tot_m = 0
tot_f = 0
for c, (m, f, tot) in results.items():
    tot_m += m
    tot_f += f
    print(f"  {c:15s}: {tot:2d} alumnos | {m:2d} V ({m*100/tot:.1f}%) | {f:2d} H ({f*100/tot:.1f}%)")

print(f"\nTOTAL INSTITUCIONAL: {tot_m + tot_f} alumnos ({tot_m} Varones / {tot_f} Hembras)")
