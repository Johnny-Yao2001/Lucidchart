"""Build the SQL Server import script and verify CSVs locally.
This validates data, not execution of T-SQL on SQL Server.
"""
from pathlib import Path
from collections import Counter, defaultdict
from decimal import Decimal
from datetime import datetime
import csv
import json
import re
from copy import deepcopy

ROOT = Path(__file__).resolve().parent
COLS = json.loads((ROOT / 'schema_columns.json').read_text())
MANIFEST = json.loads((ROOT / 'audit/manifest.json').read_text())
ROWS = {}
for table, columns in COLS.items():
    with (ROOT / 'csv' / (table + '.csv')).open(encoding='utf-8', newline='') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == columns, table
        ROWS[table] = [{k: (v if v != '' else None) for k, v in r.items()} for r in reader]

# Match nullability and field lengths of the CREATE TABLE statements already supplied.
NULLABLE = {
    'Supplier': 'Website Email',
    'Product': 'SourceProductID UnitPrice MinTempC MaxTempC GTIN',
    'ProductSupplier': 'SupplierProductCode',
    'Customer': 'Description',
    'CustomerSite': 'SiteName Address StateRegion Postcode Country Phone Email Website',
    'InventoryLot': 'ExpiryDate',
    'PickLine': 'CorrectQty VerifiedAt',
    'Shipment': 'CarrierName DispatchedAt DeliveredAt DeliveryTempC',
}
LENGTHS = {
    'Supplier': {'SupplierName': 150, 'Website': 255, 'Email': 150},
    'ProductCategory': {'CategoryName': 100},
    'ProductGroup': {'GroupName': 100, 'ProductStream': 50},
    'Product': {'SourceProductID': 50, 'Description': 500, 'UnitOfMeasure': 30, 'GTIN': 14},
    'ProductSupplier': {'SupplierProductCode': 50},
    'Warehouse': {'WarehouseName': 100, 'City': 50, 'Address': 255},
    'Worker': {'WorkerName': 100, 'EmploymentType': 30},
    'StorageLocation': {'LocationCode': 50, 'ZoneType': 50},
    'Customer': {'CustomerName': 150, 'CustomerType': 50, 'Description': 1000},
    'CustomerSite': {'SiteName': 150, 'Address': 500, 'StateRegion': 100, 'Postcode': 20, 'Country': 100, 'Phone': 100, 'Email': 254, 'Website': 500},
    'PurchaseOrder': {'Status': 30}, 'Receipt': {'Status': 30},
    'InventoryLot': {'LotCode': 80}, 'SalesOrder': {'Status': 30},
    'Shipment': {'DeliveryMethod': 30, 'CarrierName': 100},
}
FK = [
    ('Product', 'CategoryID', 'ProductCategory'), ('Product', 'ProductGroupID', 'ProductGroup'),
    ('ProductSupplier', 'ProductID', 'Product'), ('ProductSupplier', 'SupplierID', 'Supplier'),
    ('Worker', 'WarehouseID', 'Warehouse'), ('StorageLocation', 'WarehouseID', 'Warehouse'),
    ('CustomerSite', 'CustomerID', 'Customer'),
    ('PurchaseOrder', 'SupplierID', 'Supplier'), ('PurchaseOrder', 'WarehouseID', 'Warehouse'),
    ('PurchaseOrderLine', 'PurchaseOrderID', 'PurchaseOrder'), ('PurchaseOrderLine', 'ProductID', 'Product'),
    ('Receipt', 'PurchaseOrderID', 'PurchaseOrder'), ('Receipt', 'WorkerID', 'Worker'),
    ('ReceiptLine', 'ReceiptID', 'Receipt'), ('ReceiptLine', 'PurchaseOrderLineID', 'PurchaseOrderLine'),
    ('InventoryLot', 'ProductID', 'Product'),
    ('ReceiptLineLot', 'ReceiptLineID', 'ReceiptLine'), ('ReceiptLineLot', 'LotID', 'InventoryLot'),
    ('StockBalance', 'LotID', 'InventoryLot'), ('StockBalance', 'LocationID', 'StorageLocation'),
    ('TemperatureLog', 'LocationID', 'StorageLocation'),
    ('SalesOrder', 'CustomerSiteID', 'CustomerSite'), ('SalesOrder', 'WarehouseID', 'Warehouse'),
    ('SalesOrderLine', 'SalesOrderID', 'SalesOrder'), ('SalesOrderLine', 'ProductID', 'Product'),
    ('PickLine', 'SalesOrderLineID', 'SalesOrderLine'), ('PickLine', 'WorkerID', 'Worker'), ('PickLine', 'StockBalanceID', 'StockBalance'),
    ('Shipment', 'SalesOrderID', 'SalesOrder'),
    ('ShipmentLine', 'ShipmentID', 'Shipment'), ('ShipmentLine', 'SalesOrderLineID', 'SalesOrderLine'),
    ('ShipmentLineLot', 'ShipmentLineID', 'ShipmentLine'), ('ShipmentLineLot', 'LotID', 'InventoryLot'),
]
UNIQUE = {
    'ProductSupplier': ['ProductID', 'SupplierID'],
    'StorageLocation': ['WarehouseID', 'LocationCode'],
    'InventoryLot': ['ProductID', 'LotCode'],
    'ReceiptLineLot': ['ReceiptLineID', 'LotID'],
    'StockBalance': ['LotID', 'LocationID'],
    'ShipmentLineLot': ['ShipmentLineID', 'LotID'],
}

def validate(rows):
    ids = {t: {r[cols[0]]: r for r in rows[t]} for t, cols in COLS.items()}
    for t, cols in COLS.items():
        assert len(ids[t]) == len(rows[t]), 'Duplicate primary key: ' + t
        for r in rows[t]:
            for c, value in r.items():
                if value is None:
                    assert c in NULLABLE.get(t, '').split(), (t, c, 'unexpected NULL')
                    continue
                if c in LENGTHS.get(t, {}):
                    assert len(value.encode('utf-16-le')) // 2 <= LENGTHS[t][c], (t, c, 'too long')
                elif c.endswith('ID'):
                    assert str(int(value)) == value and -2147483648 <= int(value) <= 2147483647, (t, c)
                elif c in ('Discontinued', 'IsPreferred', 'IsActive'):
                    assert value in ('0', '1'), (t, c)
                elif c.endswith('At') or c == 'ExpiryDate':
                    datetime.fromisoformat(value)
                else:
                    dec = Decimal(value)
                    assert dec.is_finite() and dec == dec.quantize(Decimal('.01')), (t, c)
                    assert abs(dec) < (1000 if c.endswith('TempC') or c == 'TemperatureC' else 10**10), (t, c)
                    if c.endswith('Qty') or c in ('UnitPrice', 'UnitCost'):
                        assert dec >= 0, (t, c, 'negative quantity/price')
                    if c in ('OrderedQty', 'RequestedQty', 'PickedQty', 'ReceivedQty', 'ShippedQty'):
                        assert dec > 0, (t, c, 'nonpositive quantity')
            if r.get('MinTempC') is not None and r.get('MaxTempC') is not None:
                assert Decimal(r['MinTempC']) <= Decimal(r['MaxTempC'])
        if t in UNIQUE:
            keys = [tuple(r[c] for c in UNIQUE[t]) for r in rows[t]]
            assert len(set(keys)) == len(keys), ('Duplicate unique key', t)
    for t, column, parent in FK:
        for r in rows[t]:
            assert r[column] in ids[parent], ('Orphan FK', t, column, r[column])
    for r in rows['PurchaseOrder']:
        assert r['ExpectedAt'] >= r['OrderedAt']
    for r in rows['SalesOrder']:
        assert r['PromisedDeliveryAt'] >= r['OrderedAt']
    for r in rows['PickLine']:
        assert (r['CorrectQty'] is None) == (r['VerifiedAt'] is None)
        if r['VerifiedAt']:
            assert r['VerifiedAt'] >= r['PickedAt']
            assert Decimal(r['CorrectQty']) <= Decimal(r['PickedQty'])
        so_line = ids['SalesOrderLine'][r['SalesOrderLineID']]
        stock = ids['StockBalance'][r['StockBalanceID']]
        lot = ids['InventoryLot'][stock['LotID']]
        assert lot['ProductID'] == so_line['ProductID']
        order = ids['SalesOrder'][so_line['SalesOrderID']]
        assert ids['Worker'][r['WorkerID']]['WarehouseID'] == order['WarehouseID']
        assert ids['StorageLocation'][stock['LocationID']]['WarehouseID'] == order['WarehouseID']
    for r in rows['Receipt']:
        po = ids['PurchaseOrder'][r['PurchaseOrderID']]
        assert ids['Worker'][r['WorkerID']]['WarehouseID'] == po['WarehouseID']
        assert r['ReceivedAt'] >= po['OrderedAt']
    for r in rows['ReceiptLine']:
        assert ids['Receipt'][r['ReceiptID']]['PurchaseOrderID'] == ids['PurchaseOrderLine'][r['PurchaseOrderLineID']]['PurchaseOrderID']
        assert sum(Decimal(x['ReceivedQty']) for x in rows['ReceiptLineLot'] if x['ReceiptLineID'] == r['ReceiptLineID']) == Decimal(r['ReceivedQty'])
    for r in rows['ReceiptLineLot']:
        line = ids['ReceiptLine'][r['ReceiptLineID']]
        assert ids['PurchaseOrderLine'][line['PurchaseOrderLineID']]['ProductID'] == ids['InventoryLot'][r['LotID']]['ProductID']
    for r in rows['Shipment']:
        if r['DeliveredAt']:
            assert r['DispatchedAt'] and r['DeliveredAt'] >= r['DispatchedAt']
        if r['DispatchedAt']:
            assert r['DispatchedAt'] >= ids['SalesOrder'][r['SalesOrderID']]['OrderedAt']
            assert any(x['ShipmentID'] == r['ShipmentID'] for x in rows['ShipmentLine']), 'Dispatched shipment has no lines'
    for r in rows['ShipmentLine']:
        assert ids['Shipment'][r['ShipmentID']]['SalesOrderID'] == ids['SalesOrderLine'][r['SalesOrderLineID']]['SalesOrderID']
        assert sum(Decimal(x['ShippedQty']) for x in rows['ShipmentLineLot'] if x['ShipmentLineID'] == r['ShipmentLineID']) == Decimal(r['ShippedQty'])
    for r in rows['ShipmentLineLot']:
        line = ids['ShipmentLine'][r['ShipmentLineID']]
        assert ids['SalesOrderLine'][line['SalesOrderLineID']]['ProductID'] == ids['InventoryLot'][r['LotID']]['ProductID']
    for r in rows['PurchaseOrderLine']:
        po = ids['PurchaseOrder'][r['PurchaseOrderID']]
        assert any(ps['ProductID'] == r['ProductID'] and ps['SupplierID'] == po['SupplierID'] for ps in rows['ProductSupplier'])
        received = sum(Decimal(x['ReceivedQty']) for x in rows['ReceiptLine'] if x['PurchaseOrderLineID'] == r['PurchaseOrderLineID'])
        assert received <= Decimal(r['OrderedQty'])
        if po['Status'] == 'Completed':
            assert received == Decimal(r['OrderedQty'])
    for r in rows['SalesOrderLine']:
        shipped = sum(Decimal(x['ShippedQty']) for x in rows['ShipmentLine'] if x['SalesOrderLineID'] == r['SalesOrderLineID'])
        assert shipped <= Decimal(r['RequestedQty'])
        if ids['SalesOrder'][r['SalesOrderID']]['Status'] == 'Completed':
            assert shipped == Decimal(r['RequestedQty'])
    for lot in rows['InventoryLot']:
        received = sum(Decimal(r['ReceivedQty']) for r in rows['ReceiptLineLot'] if r['LotID'] == lot['LotID'])
        shipped = sum(Decimal(r['ShippedQty']) for r in rows['ShipmentLineLot'] if r['LotID'] == lot['LotID'])
        balance = sum(Decimal(r['OnHandQty']) for r in rows['StockBalance'] if r['LotID'] == lot['LotID'])
        assert received - shipped == balance, ('Inventory reconciliation', lot['LotID'])

validate(ROWS)
negative_checks = []
for label, mutation in [
    ('orphan_foreign_key', lambda d: d['PickLine'][0].update(WorkerID='999999')),
    ('negative_stock', lambda d: d['StockBalance'][0].update(OnHandQty='-1')),
    ('batch_quantity_mismatch', lambda d: d['ReceiptLineLot'][0].update(ReceivedQty='99')),
    ('verified_without_correct_quantity', lambda d: d['PickLine'][0].update(CorrectQty=None)),
    ('cross_product_pick', lambda d: d['PickLine'][0].update(StockBalanceID='2')),
]:
    invalid = deepcopy(ROWS)
    mutation(invalid)
    try:
        validate(invalid)
    except AssertionError:
        negative_checks.append(label)
    else:
        raise AssertionError('Invalid fixture escaped validation: ' + label)

verified = [r for r in ROWS['PickLine'] if r['VerifiedAt']]
picked = sum(Decimal(r['PickedQty']) for r in verified)
correct = sum(Decimal(r['CorrectQty']) for r in verified)
assert picked == 50 and correct == 48
delivered = [r for r in ROWS['Shipment'] if r['DeliveredAt']]
sales = {r['SalesOrderID']: r for r in ROWS['SalesOrder']}
on_time = sum(r['DeliveredAt'] <= sales[r['SalesOrderID']]['PromisedDeliveryAt'] for r in delivered)
assert len(delivered) == 3 and on_time == 2
complete = [r for r in ROWS['PurchaseOrder'] if r['Status'] == 'Completed']
receipt_on_time = sum(max(x['ReceivedAt'] for x in ROWS['Receipt'] if x['PurchaseOrderID'] == r['PurchaseOrderID']) <= r['ExpectedAt'] for r in complete)
assert len(complete) == 4 and receipt_on_time == 3
occupied = {r['LocationID'] for r in ROWS['StockBalance'] if Decimal(r['OnHandQty']) > 0}
utilization = {}
for w in ROWS['Warehouse']:
    locations = [l for l in ROWS['StorageLocation'] if l['WarehouseID'] == w['WarehouseID'] and l['IsActive'] == '1']
    utilization[w['WarehouseID']] = [sum(l['LocationID'] in occupied for l in locations), len(locations)]
assert utilization == {'1': [2, 2], '2': [1, 2]}

sql = [r'''/* Append this complete script to ApromoWMS_Assignment.sql.
Run ONLY this import section once, after all 24 tables have been created.
Requires the exact schema supplied in the chat, SQL Server 2017+ and bulk-load permission.
Extract the ZIP so files are at C:\ApromoWMS\csv\Supplier.csv, etc.
The SQL SERVER SERVICE ACCOUNT must have read access to that folder.
No files are read from GitHub by SQL Server. All paths are on the server machine.
This import refuses to proceed if any target table contains data.
It never deletes existing rows or disables constraints.
*/
USE ApromoWMS;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;

-- Change only this path if the extraction location differs; keep the trailing backslash.
DECLARE @CsvFolder nvarchar(4000) = N'C:\ApromoWMS\csv\';

DECLARE @Expected TABLE (
    LoadOrder int PRIMARY KEY,
    TableName sysname NOT NULL,
    ExpectedRows int NOT NULL
);
INSERT INTO @Expected (LoadOrder, TableName, ExpectedRows) VALUES''']
sql.append(',\n'.join(f"({i}, N'{t}', {len(ROWS[t])})" for i, t in enumerate(COLS, 1)) + ';')
sql.append(r"""
DECLARE @TableName sysname, @ExpectedRows int, @ActualRows bigint;
DECLARE @Sql nvarchar(max), @Message nvarchar(2048);
DECLARE load_tables CURSOR LOCAL FAST_FORWARD FOR
    SELECT TableName, ExpectedRows FROM @Expected ORDER BY LoadOrder;

BEGIN TRY
    BEGIN TRANSACTION;
    -- Preflight all tables before loading any rows.
    OPEN load_tables;
    FETCH NEXT FROM load_tables INTO @TableName, @ExpectedRows;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF OBJECT_ID(N'dbo.' + QUOTENAME(@TableName), N'U') IS NULL
        BEGIN
            SET @Message = N'Missing table: dbo.' + @TableName;
            THROW 51000, @Message, 1;
        END;
        SET @Sql = N'SELECT @n = COUNT_BIG(*) FROM dbo.' + QUOTENAME(@TableName) + N';';
        EXEC sys.sp_executesql @Sql, N'@n bigint OUTPUT', @n = @ActualRows OUTPUT;
        IF @ActualRows <> 0
        BEGIN
            SET @Message = N'Import cancelled: dbo.' + @TableName + N' already contains data. No rows deleted.';
            THROW 51001, @Message, 1;
        END;
        FETCH NEXT FROM load_tables INTO @TableName, @ExpectedRows;
    END;
    CLOSE load_tables;

    OPEN load_tables;
    FETCH NEXT FROM load_tables INTO @TableName, @ExpectedRows;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @Sql = N'BULK INSERT dbo.' + QUOTENAME(@TableName)
            + N' FROM ''' + REPLACE(@CsvFolder + @TableName + N'.csv', N'''', N'''''')
            + N''' WITH (FORMAT = ''CSV'', FIRSTROW = 2, CODEPAGE = ''65001'', '
            + N'FIELDQUOTE = ''"'', FIELDTERMINATOR = '','', ROWTERMINATOR = ''0x0a'', '
            + N'KEEPNULLS, CHECK_CONSTRAINTS, TABLOCK);';
        EXEC sys.sp_executesql @Sql;
        SET @Sql = N'SELECT @n = COUNT_BIG(*) FROM dbo.' + QUOTENAME(@TableName) + N';';
        EXEC sys.sp_executesql @Sql, N'@n bigint OUTPUT', @n = @ActualRows OUTPUT;
        IF @ActualRows <> @ExpectedRows
        BEGIN
            SET @Message = N'Row count mismatch: dbo.' + @TableName
                + N'. Expected ' + CONVERT(nvarchar(20), @ExpectedRows)
                + N', actual ' + CONVERT(nvarchar(20), @ActualRows) + N'.';
            THROW 51002, @Message, 1;
        END;
        PRINT N'Loaded dbo.' + @TableName + N': ' + CONVERT(nvarchar(20), @ActualRows) + N' rows';
        FETCH NEXT FROM load_tables INTO @TableName, @ExpectedRows;
    END;
    CLOSE load_tables;
    DEALLOCATE load_tables;
""")

# Cross-table business rules that ordinary FKs do not enforce.
checks = [
    ('Receipt belongs to wrong purchase order', '''SELECT 1 FROM dbo.ReceiptLine rl JOIN dbo.Receipt r ON r.ReceiptID=rl.ReceiptID JOIN dbo.PurchaseOrderLine pl ON pl.PurchaseOrderLineID=rl.PurchaseOrderLineID WHERE r.PurchaseOrderID<>pl.PurchaseOrderID'''),
    ('Receipt batch product mismatch', '''SELECT 1 FROM dbo.ReceiptLineLot x JOIN dbo.ReceiptLine rl ON rl.ReceiptLineID=x.ReceiptLineID JOIN dbo.PurchaseOrderLine pl ON pl.PurchaseOrderLineID=rl.PurchaseOrderLineID JOIN dbo.InventoryLot l ON l.LotID=x.LotID WHERE pl.ProductID<>l.ProductID'''),
    ('Receipt batch quantities do not sum to line quantity', '''SELECT 1 FROM dbo.ReceiptLine rl LEFT JOIN dbo.ReceiptLineLot x ON x.ReceiptLineID=rl.ReceiptLineID GROUP BY rl.ReceiptLineID,rl.ReceivedQty HAVING COALESCE(SUM(x.ReceivedQty),0)<>rl.ReceivedQty'''),
    ('Shipment belongs to wrong sales order', '''SELECT 1 FROM dbo.ShipmentLine sl JOIN dbo.Shipment s ON s.ShipmentID=sl.ShipmentID JOIN dbo.SalesOrderLine ol ON ol.SalesOrderLineID=sl.SalesOrderLineID WHERE s.SalesOrderID<>ol.SalesOrderID'''),
    ('Shipment batch product mismatch', '''SELECT 1 FROM dbo.ShipmentLineLot x JOIN dbo.ShipmentLine sl ON sl.ShipmentLineID=x.ShipmentLineID JOIN dbo.SalesOrderLine ol ON ol.SalesOrderLineID=sl.SalesOrderLineID JOIN dbo.InventoryLot l ON l.LotID=x.LotID WHERE ol.ProductID<>l.ProductID'''),
    ('Shipment batch quantities do not sum to line quantity', '''SELECT 1 FROM dbo.ShipmentLine sl LEFT JOIN dbo.ShipmentLineLot x ON x.ShipmentLineID=sl.ShipmentLineID GROUP BY sl.ShipmentLineID,sl.ShippedQty HAVING COALESCE(SUM(x.ShippedQty),0)<>sl.ShippedQty'''),
    ('Pick batch product mismatch', '''SELECT 1 FROM dbo.PickLine p JOIN dbo.SalesOrderLine ol ON ol.SalesOrderLineID=p.SalesOrderLineID JOIN dbo.StockBalance sb ON sb.StockBalanceID=p.StockBalanceID JOIN dbo.InventoryLot l ON l.LotID=sb.LotID WHERE l.ProductID<>ol.ProductID'''),
    ('Pick warehouse mismatch', '''SELECT 1 FROM dbo.PickLine p JOIN dbo.Worker w ON w.WorkerID=p.WorkerID JOIN dbo.StockBalance sb ON sb.StockBalanceID=p.StockBalanceID JOIN dbo.StorageLocation loc ON loc.LocationID=sb.LocationID JOIN dbo.SalesOrderLine ol ON ol.SalesOrderLineID=p.SalesOrderLineID JOIN dbo.SalesOrder o ON o.SalesOrderID=ol.SalesOrderID WHERE w.WarehouseID<>o.WarehouseID OR loc.WarehouseID<>o.WarehouseID'''),
    ('Receipt warehouse mismatch', '''SELECT 1 FROM dbo.Receipt r JOIN dbo.PurchaseOrder po ON po.PurchaseOrderID=r.PurchaseOrderID JOIN dbo.Worker w ON w.WorkerID=r.WorkerID WHERE w.WarehouseID<>po.WarehouseID'''),
    ('Purchase order supplier not linked to product', '''SELECT 1 FROM dbo.PurchaseOrderLine pl JOIN dbo.PurchaseOrder po ON po.PurchaseOrderID=pl.PurchaseOrderID WHERE NOT EXISTS (SELECT 1 FROM dbo.ProductSupplier ps WHERE ps.ProductID=pl.ProductID AND ps.SupplierID=po.SupplierID)'''),
    ('Inventory does not reconcile to receipts minus shipments', '''SELECT 1 FROM dbo.InventoryLot l OUTER APPLY (SELECT SUM(x.ReceivedQty) AS Qty FROM dbo.ReceiptLineLot x WHERE x.LotID=l.LotID) r OUTER APPLY (SELECT SUM(x.ShippedQty) AS Qty FROM dbo.ShipmentLineLot x WHERE x.LotID=l.LotID) s OUTER APPLY (SELECT SUM(x.OnHandQty) AS Qty FROM dbo.StockBalance x WHERE x.LotID=l.LotID) b WHERE COALESCE(r.Qty,0)-COALESCE(s.Qty,0)<>COALESCE(b.Qty,0)'''),
    ('Purchase order receipt quantity invalid', '''SELECT 1 FROM dbo.PurchaseOrderLine pl JOIN dbo.PurchaseOrder po ON po.PurchaseOrderID=pl.PurchaseOrderID OUTER APPLY (SELECT SUM(rl.ReceivedQty) AS Qty FROM dbo.ReceiptLine rl WHERE rl.PurchaseOrderLineID=pl.PurchaseOrderLineID) r WHERE COALESCE(r.Qty,0)>pl.OrderedQty OR (po.Status=N'Completed' AND COALESCE(r.Qty,0)<>pl.OrderedQty)'''),
    ('Sales order shipment quantity invalid', '''SELECT 1 FROM dbo.SalesOrderLine ol JOIN dbo.SalesOrder o ON o.SalesOrderID=ol.SalesOrderID OUTER APPLY (SELECT SUM(sl.ShippedQty) AS Qty FROM dbo.ShipmentLine sl WHERE sl.SalesOrderLineID=ol.SalesOrderLineID) s WHERE COALESCE(s.Qty,0)>ol.RequestedQty OR (o.Status=N'Completed' AND COALESCE(s.Qty,0)<>ol.RequestedQty)'''),
]
for message, query in checks:
    sql.append(f"    IF EXISTS (\n        {query}\n    )\n        THROW 51003, N'{message}', 1;\n")
sql.append(r'''
    IF EXISTS (
        SELECT 1 FROM sys.foreign_keys
        WHERE parent_object_id IN (
            SELECT OBJECT_ID(N'dbo.' + QUOTENAME(TableName)) FROM @Expected
        ) AND (is_disabled=1 OR is_not_trusted=1)
    )
        THROW 51004, N'Foreign keys must remain enabled and trusted.', 1;

    COMMIT TRANSACTION;
    SELECT N'IMPORT PASSED' AS ImportStatus,
           (SELECT COUNT(*) FROM @Expected) AS TablesLoaded;
    -- These counts are verified against the actual tables before commit.
    SELECT TableName, ExpectedRows AS VerifiedRows
    FROM @Expected ORDER BY LoadOrder;
    SELECT COUNT(*) AS ForeignKeyCount,
           SUM(CASE WHEN is_disabled=1 OR is_not_trusted=1 THEN 1 ELSE 0 END) AS DisabledOrUntrusted
    FROM sys.foreign_keys
    WHERE parent_object_id IN (
        SELECT OBJECT_ID(N'dbo.' + QUOTENAME(TableName)) FROM @Expected
    );
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    IF CURSOR_STATUS('local','load_tables') >= 0 CLOSE load_tables;
    IF CURSOR_STATUS('local','load_tables') >= -1 DEALLOCATE load_tables;
    THROW;
END CATCH;
GO
''')
(ROOT / '02_Import_CSV.sql').write_text('\n'.join(sql), encoding='utf-8-sig')
report = {'csv_tables_validated': len(ROWS), 'rows_validated': sum(map(len, ROWS.values())), 'foreign_key_relationships_checked': len(FK), 'negative_cases_rejected': negative_checks, 'business_rule_sql_checks_generated': len(checks), 'fixture_metric_assertions': 'passed', 'sql_server_execution': 'NOT RUN: run the import on the user Windows SQL Server Express instance.'}
(ROOT / 'audit' / 'local_validation.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
print(json.dumps(report, indent=2))
