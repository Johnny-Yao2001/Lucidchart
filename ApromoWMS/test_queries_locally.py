"""Exercise query logic with SQLite using the uploaded SQL's table constraints.
SQLite is an independent logic check, NOT SQL Server execution evidence.
Usage: python test_queries_locally.py /path/to/ApromoWMS_Assignment.sql
"""
from pathlib import Path
import csv
import json
import re
import sqlite3
import sys

root = Path(__file__).resolve().parent
schema_path = Path(sys.argv[1])
schema = schema_path.read_text(encoding='utf-8-sig')
tables = re.findall(r'CREATE TABLE dbo\.(\w+)\s*\((.*?)\n    \);', schema, re.S)
columns = json.loads((root / 'schema_columns.json').read_text())
assert len(tables) == 24
db = sqlite3.connect(':memory:')
db.row_factory = sqlite3.Row
db.execute('PRAGMA foreign_keys=ON')
for table, body in tables:
    # SQLite accepts the declared type names, PK/FK, UNIQUE and CHECK syntax here.
    db.execute('CREATE TABLE ' + table + ' (' + body.replace('dbo.', '') + ')')
for table, cols in columns.items():
    with (root / 'csv' / (table + '.csv')).open(encoding='utf-8', newline='') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == cols
        values = [[None if r[c] == '' else r[c] for c in cols] for r in reader]
    db.executemany('INSERT INTO ' + table + ' VALUES (' + ','.join('?' for _ in cols) + ')', values)
assert db.execute('PRAGMA foreign_key_check').fetchall() == []

sql = (root / '03_DQL_Queries.sql').read_text(encoding='utf-8-sig')
batches = re.split(r'^GO\s*$', sql, flags=re.M)
queries = []
for batch in batches:
    batch = re.sub(r'/\*.*?\*/', '', batch, flags=re.S)
    batch = re.sub(r'^USE .*?;', '', batch, flags=re.M)
    batch = re.sub(r'^DECLARE .*?;', '', batch, flags=re.M)
    batch = batch.replace('dbo.', '').replace("N'", "'")
    for name, value in {'@StartDate': '2026-03-01T00:00:00', '@EndDate': '2026-04-01T00:00:00', '@AsOf': '2026-03-12T12:00:00'}.items():
        batch = batch.replace(name, "'" + value + "'")
    batch = batch.strip()
    if batch:
        queries.append(batch)
assert len(queries) == 4

def results(index):
    return [dict(r) for r in db.execute(queries[index])]

observed = [results(i) for i in range(4)]
q1, q2, q3, q4 = observed
assert q1[0]['TotalPickLines'] == 5
assert q1[0]['VerifiedPickLines'] == 4
assert q1[0]['UnverifiedPickLines'] == 1
assert q1[0]['UnitPickingAccuracyPct'] == 96
assert q1[0]['FullyCorrectLinePct'] == 75
assert q2[0]['DueShipments'] == 4
assert q2[0]['OverdueUndeliveredShipments'] == 1
assert q2[0]['DueShipmentOnTimePct'] == 50
assert round(q2[0]['DeliveredOnlyOnTimePct'], 2) == 66.67
assert q3[0]['DuePurchaseOrders'] == 5
assert q3[0]['OverdueIncompleteOrders'] == 1
assert q3[0]['DueOrderOnTimeReceiptPct'] == 60
assert q3[0]['CompletedOnlyOnTimeReceiptPct'] == 75
assert [r['CurrentCapacityUsedPct'] for r in q4] == [100, 50]

edge_cases = []
db.execute('SAVEPOINT edge')
db.execute("UPDATE PickLine SET CorrectQty=5,VerifiedAt='2026-03-13T12:00:00' WHERE PickLineID=5")
assert results(0) == q1
db.execute('ROLLBACK TO edge')
edge_cases.append('verification_after_cutoff_excluded')

db.execute("INSERT INTO Receipt VALUES (99,5,1,'2026-03-13T09:00:00','Completed')")
db.execute('INSERT INTO ReceiptLine VALUES (99,99,5,60)')
assert results(2) == q3
db.execute('ROLLBACK TO edge')
edge_cases.append('receipt_after_cutoff_excluded')

db.execute('UPDATE StockBalance SET OnHandQty=0 WHERE LocationID=2')
assert results(3)[0]['CurrentCapacityUsedPct'] == 50
db.execute('ROLLBACK TO edge')
edge_cases.append('zero_quantity_location_counts_as_empty')

db.execute('DELETE FROM PickLine')
empty = results(0)[0]
assert empty['TotalPickLines'] == 0 and empty['UnitPickingAccuracyPct'] is None
db.execute('ROLLBACK TO edge')
edge_cases.append('empty_picking_scope_returns_NULL_rate')

db.execute("UPDATE StorageLocation SET IsActive=0 WHERE WarehouseID=2")
no_capacity = results(3)[1]
assert no_capacity['ActiveStorageLocations'] == 0 and no_capacity['CurrentCapacityUsedPct'] is None
db.execute('ROLLBACK TO edge')
edge_cases.append('zero_active_capacity_returns_NULL_rate')

db.execute('RELEASE edge')
report = {
    'engine': 'SQLite in-memory; independently verifies query logic and sample outputs only',
    'schema_tables': len(tables),
    'foreign_key_check': 'passed',
    'queries_executed': 4,
    'results': observed,
    'edge_cases_passed': edge_cases,
    'sql_server_execution': 'NOT RUN: official image layers blocked by network proxy (403). SQL Server-specific syntax and BULK INSERT still require SSMS confirmation.',
}
(root / 'audit' / 'query_logic_validation.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(report, ensure_ascii=False, indent=2))
