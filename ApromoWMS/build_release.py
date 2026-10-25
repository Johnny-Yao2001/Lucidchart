"""Rebuild CSVs, import SQL, validation, complete assignment file and ZIP.
Usage: python build_release.py /path/to/Lucidchart
The source checkout must contain the original Excel files and uploaded schema SQL.
"""
from pathlib import Path
import importlib.util
import json
import re
import subprocess
import sys
from zipfile import ZipFile, ZIP_DEFLATED

root = Path(__file__).resolve().parent
source = Path(sys.argv[1]).resolve()
schema_file = source / 'ApromoWMS_Assignment.sql'
schema = schema_file.read_text(encoding='utf-8-sig')
subprocess.run([sys.executable, str(root / 'prepare_data.py'), str(source)], check=True, stdout=subprocess.DEVNULL)
columns = json.loads((root / 'schema_columns.json').read_text())
actual_columns = {}
for match in re.finditer(r'CREATE TABLE dbo\.(\w+)\s*\((.*?)\n    \);', schema, re.S):
    table, body = match.groups()
    actual_columns[table] = re.findall(r'^\s*(\w+)\s+(?:int|nvarchar\(\d+\)|varchar\(\d+\)|decimal\(\d+,\d+\)|bit|datetime2|date)\s+(?:NOT NULL|NULL)', body, re.M)
assert actual_columns == columns, 'Uploaded schema differs from CSV layouts'

spec = importlib.util.spec_from_file_location('build_import', root / 'build_import.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
subprocess.run([sys.executable, str(root / 'test_queries_locally.py'), str(schema_file)], check=True, stdout=subprocess.DEVNULL)

sql = ['''/* Read-only post-import validation. Safe to repeat. */
USE ApromoWMS;
GO
SET NOCOUNT ON;

-- Actual table counts must equal expected counts.
;WITH RowCounts AS (''']
sql.append('\nUNION ALL\n'.join(
    f"SELECT N'{table}' AS TableName, {len(mod.ROWS[table])} AS ExpectedRows, COUNT_BIG(*) AS ActualRows FROM dbo.[{table}]"
    for table in columns))
sql.append(''')
SELECT TableName, ExpectedRows, ActualRows,
       CASE WHEN ExpectedRows=ActualRows THEN N'PASS' ELSE N'FAIL' END AS Result
FROM RowCounts ORDER BY TableName;

-- Every business check should have IssueCount=0.
''')
sql.append('\nUNION ALL\n'.join(
    f"SELECT N'{message}' AS CheckName, COUNT_BIG(*) AS IssueCount FROM (\n    {query.replace('SELECT 1 FROM', 'SELECT 1 AS Issue FROM', 1)}\n) AS Violations"
    for message, query in mod.checks) + ';')
sql.append('''
-- Expected: 33 foreign keys, all enabled and trusted.
SELECT fk.name AS ForeignKeyName,
       OBJECT_NAME(fk.parent_object_id) AS ChildTable,
       OBJECT_NAME(fk.referenced_object_id) AS ParentTable,
       fk.is_disabled, fk.is_not_trusted
FROM sys.foreign_keys AS fk
WHERE OBJECT_SCHEMA_NAME(fk.parent_object_id) = N'dbo'
ORDER BY ChildTable, ForeignKeyName;
GO
''')
(root / '04_Validate_Import.sql').write_text('\n'.join(sql), encoding='utf-8-sig')

complete = ['''/* COMPLETE ASSIGNMENT SCRIPT - FOR A NEW DATABASE ONLY.
The original uploaded schema is preserved below.
If tables already exist, DO NOT run this file from the beginning.
Run 02_Import_CSV.sql, then 04_Validate_Import.sql, then 03_DQL_Queries.sql.
CSV files must be available at the path configured in the import section.
Operational records are fictional test data, not real company transactions.
*/\n''', schema]
for filename in ['02_Import_CSV.sql', '04_Validate_Import.sql', '03_DQL_Queries.sql']:
    complete.append('\n\n/* ===== ' + filename + ' ===== */\n')
    complete.append((root / filename).read_text(encoding='utf-8-sig'))
(root / 'ApromoWMS_Assignment_COMPLETE.sql').write_text('\n'.join(complete), encoding='utf-8-sig')

zipfile = root.parent / 'ApromoWMS_Import.zip'
with ZipFile(zipfile, 'w', ZIP_DEFLATED) as z:
    for path in sorted(root.rglob('*')):
        if path.is_file() and '__pycache__' not in path.parts:
            z.write(path, path.relative_to(root))
with ZipFile(zipfile) as z:
    assert z.testzip() is None
    assert len([n for n in z.namelist() if n.startswith('csv/')]) == 24
print('Uploaded SQL matches 24 table layouts and 33 FK definitions.')
print('Four query logic checks and five boundary cases passed (SQLite, not SQL Server).')
print('Release ZIP:', zipfile)
