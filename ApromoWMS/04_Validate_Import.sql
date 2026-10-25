/* Read-only post-import validation. Safe to repeat. */
USE ApromoWMS;
GO
SET NOCOUNT ON;

-- Actual table counts must equal expected counts.
;WITH RowCounts AS (
SELECT N'Supplier' AS TableName, 82 AS ExpectedRows, COUNT_BIG(*) AS ActualRows FROM dbo.[Supplier]
UNION ALL
SELECT N'ProductCategory' AS TableName, 41 AS ExpectedRows, COUNT_BIG(*) AS ActualRows FROM dbo.[ProductCategory]
UNION ALL
SELECT N'ProductGroup' AS TableName, 14 AS ExpectedRows, COUNT_BIG(*) AS ActualRows FROM dbo.[ProductGroup]
UNION ALL
SELECT N'Product' AS TableName, 1008 AS ExpectedRows, COUNT_BIG(*) AS ActualRows FROM dbo.[Product]
UNION ALL
SELECT N'ProductSupplier' AS TableName, 1008 AS ExpectedRows, COUNT_BIG(*) AS ActualRows FROM dbo.[ProductSupplier]
UNION ALL
SELECT N'Warehouse' AS TableName, 2 AS ExpectedRows, COUNT_BIG(*) AS ActualRows FROM dbo.[Warehouse]
UNION ALL
SELECT N'Worker' AS TableName, 5 AS ExpectedRows, COUNT_BIG(*) AS ActualRows FROM dbo.[Worker]
UNION ALL
SELECT N'StorageLocation' AS TableName, 4 AS ExpectedRows, COUNT_BIG(*) AS ActualRows FROM dbo.[StorageLocation]
UNION ALL
SELECT N'Customer' AS TableName, 152 AS ExpectedRows, COUNT_BIG(*) AS ActualRows FROM dbo.[Customer]
UNION ALL
SELECT N'CustomerSite' AS TableName, 176 AS ExpectedRows, COUNT_BIG(*) AS ActualRows FROM dbo.[CustomerSite]
UNION ALL
SELECT N'PurchaseOrder' AS TableName, 5 AS ExpectedRows, COUNT_BIG(*) AS ActualRows FROM dbo.[PurchaseOrder]
UNION ALL
SELECT N'PurchaseOrderLine' AS TableName, 5 AS ExpectedRows, COUNT_BIG(*) AS ActualRows FROM dbo.[PurchaseOrderLine]
UNION ALL
SELECT N'Receipt' AS TableName, 5 AS ExpectedRows, COUNT_BIG(*) AS ActualRows FROM dbo.[Receipt]
UNION ALL
SELECT N'ReceiptLine' AS TableName, 5 AS ExpectedRows, COUNT_BIG(*) AS ActualRows FROM dbo.[ReceiptLine]
UNION ALL
SELECT N'InventoryLot' AS TableName, 5 AS ExpectedRows, COUNT_BIG(*) AS ActualRows FROM dbo.[InventoryLot]
UNION ALL
SELECT N'ReceiptLineLot' AS TableName, 5 AS ExpectedRows, COUNT_BIG(*) AS ActualRows FROM dbo.[ReceiptLineLot]
UNION ALL
SELECT N'StockBalance' AS TableName, 5 AS ExpectedRows, COUNT_BIG(*) AS ActualRows FROM dbo.[StockBalance]
UNION ALL
SELECT N'TemperatureLog' AS TableName, 5 AS ExpectedRows, COUNT_BIG(*) AS ActualRows FROM dbo.[TemperatureLog]
UNION ALL
SELECT N'SalesOrder' AS TableName, 5 AS ExpectedRows, COUNT_BIG(*) AS ActualRows FROM dbo.[SalesOrder]
UNION ALL
SELECT N'SalesOrderLine' AS TableName, 5 AS ExpectedRows, COUNT_BIG(*) AS ActualRows FROM dbo.[SalesOrderLine]
UNION ALL
SELECT N'PickLine' AS TableName, 5 AS ExpectedRows, COUNT_BIG(*) AS ActualRows FROM dbo.[PickLine]
UNION ALL
SELECT N'Shipment' AS TableName, 5 AS ExpectedRows, COUNT_BIG(*) AS ActualRows FROM dbo.[Shipment]
UNION ALL
SELECT N'ShipmentLine' AS TableName, 3 AS ExpectedRows, COUNT_BIG(*) AS ActualRows FROM dbo.[ShipmentLine]
UNION ALL
SELECT N'ShipmentLineLot' AS TableName, 3 AS ExpectedRows, COUNT_BIG(*) AS ActualRows FROM dbo.[ShipmentLineLot]
)
SELECT TableName, ExpectedRows, ActualRows,
       CASE WHEN ExpectedRows=ActualRows THEN N'PASS' ELSE N'FAIL' END AS Result
FROM RowCounts ORDER BY TableName;

-- Every business check should have IssueCount=0.

SELECT N'Receipt belongs to wrong purchase order' AS CheckName, COUNT_BIG(*) AS IssueCount FROM (
    SELECT 1 AS Issue FROM dbo.ReceiptLine rl JOIN dbo.Receipt r ON r.ReceiptID=rl.ReceiptID JOIN dbo.PurchaseOrderLine pl ON pl.PurchaseOrderLineID=rl.PurchaseOrderLineID WHERE r.PurchaseOrderID<>pl.PurchaseOrderID
) AS Violations
UNION ALL
SELECT N'Receipt batch product mismatch' AS CheckName, COUNT_BIG(*) AS IssueCount FROM (
    SELECT 1 AS Issue FROM dbo.ReceiptLineLot x JOIN dbo.ReceiptLine rl ON rl.ReceiptLineID=x.ReceiptLineID JOIN dbo.PurchaseOrderLine pl ON pl.PurchaseOrderLineID=rl.PurchaseOrderLineID JOIN dbo.InventoryLot l ON l.LotID=x.LotID WHERE pl.ProductID<>l.ProductID
) AS Violations
UNION ALL
SELECT N'Receipt batch quantities do not sum to line quantity' AS CheckName, COUNT_BIG(*) AS IssueCount FROM (
    SELECT 1 AS Issue FROM dbo.ReceiptLine rl LEFT JOIN dbo.ReceiptLineLot x ON x.ReceiptLineID=rl.ReceiptLineID GROUP BY rl.ReceiptLineID,rl.ReceivedQty HAVING COALESCE(SUM(x.ReceivedQty),0)<>rl.ReceivedQty
) AS Violations
UNION ALL
SELECT N'Shipment belongs to wrong sales order' AS CheckName, COUNT_BIG(*) AS IssueCount FROM (
    SELECT 1 AS Issue FROM dbo.ShipmentLine sl JOIN dbo.Shipment s ON s.ShipmentID=sl.ShipmentID JOIN dbo.SalesOrderLine ol ON ol.SalesOrderLineID=sl.SalesOrderLineID WHERE s.SalesOrderID<>ol.SalesOrderID
) AS Violations
UNION ALL
SELECT N'Shipment batch product mismatch' AS CheckName, COUNT_BIG(*) AS IssueCount FROM (
    SELECT 1 AS Issue FROM dbo.ShipmentLineLot x JOIN dbo.ShipmentLine sl ON sl.ShipmentLineID=x.ShipmentLineID JOIN dbo.SalesOrderLine ol ON ol.SalesOrderLineID=sl.SalesOrderLineID JOIN dbo.InventoryLot l ON l.LotID=x.LotID WHERE ol.ProductID<>l.ProductID
) AS Violations
UNION ALL
SELECT N'Shipment batch quantities do not sum to line quantity' AS CheckName, COUNT_BIG(*) AS IssueCount FROM (
    SELECT 1 AS Issue FROM dbo.ShipmentLine sl LEFT JOIN dbo.ShipmentLineLot x ON x.ShipmentLineID=sl.ShipmentLineID GROUP BY sl.ShipmentLineID,sl.ShippedQty HAVING COALESCE(SUM(x.ShippedQty),0)<>sl.ShippedQty
) AS Violations
UNION ALL
SELECT N'Pick batch product mismatch' AS CheckName, COUNT_BIG(*) AS IssueCount FROM (
    SELECT 1 AS Issue FROM dbo.PickLine p JOIN dbo.SalesOrderLine ol ON ol.SalesOrderLineID=p.SalesOrderLineID JOIN dbo.StockBalance sb ON sb.StockBalanceID=p.StockBalanceID JOIN dbo.InventoryLot l ON l.LotID=sb.LotID WHERE l.ProductID<>ol.ProductID
) AS Violations
UNION ALL
SELECT N'Pick warehouse mismatch' AS CheckName, COUNT_BIG(*) AS IssueCount FROM (
    SELECT 1 AS Issue FROM dbo.PickLine p JOIN dbo.Worker w ON w.WorkerID=p.WorkerID JOIN dbo.StockBalance sb ON sb.StockBalanceID=p.StockBalanceID JOIN dbo.StorageLocation loc ON loc.LocationID=sb.LocationID JOIN dbo.SalesOrderLine ol ON ol.SalesOrderLineID=p.SalesOrderLineID JOIN dbo.SalesOrder o ON o.SalesOrderID=ol.SalesOrderID WHERE w.WarehouseID<>o.WarehouseID OR loc.WarehouseID<>o.WarehouseID
) AS Violations
UNION ALL
SELECT N'Receipt warehouse mismatch' AS CheckName, COUNT_BIG(*) AS IssueCount FROM (
    SELECT 1 AS Issue FROM dbo.Receipt r JOIN dbo.PurchaseOrder po ON po.PurchaseOrderID=r.PurchaseOrderID JOIN dbo.Worker w ON w.WorkerID=r.WorkerID WHERE w.WarehouseID<>po.WarehouseID
) AS Violations
UNION ALL
SELECT N'Purchase order supplier not linked to product' AS CheckName, COUNT_BIG(*) AS IssueCount FROM (
    SELECT 1 AS Issue FROM dbo.PurchaseOrderLine pl JOIN dbo.PurchaseOrder po ON po.PurchaseOrderID=pl.PurchaseOrderID WHERE NOT EXISTS (SELECT 1 FROM dbo.ProductSupplier ps WHERE ps.ProductID=pl.ProductID AND ps.SupplierID=po.SupplierID)
) AS Violations
UNION ALL
SELECT N'Inventory does not reconcile to receipts minus shipments' AS CheckName, COUNT_BIG(*) AS IssueCount FROM (
    SELECT 1 AS Issue FROM dbo.InventoryLot l OUTER APPLY (SELECT SUM(x.ReceivedQty) AS Qty FROM dbo.ReceiptLineLot x WHERE x.LotID=l.LotID) r OUTER APPLY (SELECT SUM(x.ShippedQty) AS Qty FROM dbo.ShipmentLineLot x WHERE x.LotID=l.LotID) s OUTER APPLY (SELECT SUM(x.OnHandQty) AS Qty FROM dbo.StockBalance x WHERE x.LotID=l.LotID) b WHERE COALESCE(r.Qty,0)-COALESCE(s.Qty,0)<>COALESCE(b.Qty,0)
) AS Violations
UNION ALL
SELECT N'Purchase order receipt quantity invalid' AS CheckName, COUNT_BIG(*) AS IssueCount FROM (
    SELECT 1 AS Issue FROM dbo.PurchaseOrderLine pl JOIN dbo.PurchaseOrder po ON po.PurchaseOrderID=pl.PurchaseOrderID OUTER APPLY (SELECT SUM(rl.ReceivedQty) AS Qty FROM dbo.ReceiptLine rl WHERE rl.PurchaseOrderLineID=pl.PurchaseOrderLineID) r WHERE COALESCE(r.Qty,0)>pl.OrderedQty OR (po.Status=N'Completed' AND COALESCE(r.Qty,0)<>pl.OrderedQty)
) AS Violations
UNION ALL
SELECT N'Sales order shipment quantity invalid' AS CheckName, COUNT_BIG(*) AS IssueCount FROM (
    SELECT 1 AS Issue FROM dbo.SalesOrderLine ol JOIN dbo.SalesOrder o ON o.SalesOrderID=ol.SalesOrderID OUTER APPLY (SELECT SUM(sl.ShippedQty) AS Qty FROM dbo.ShipmentLine sl WHERE sl.SalesOrderLineID=ol.SalesOrderLineID) s WHERE COALESCE(s.Qty,0)>ol.RequestedQty OR (o.Status=N'Completed' AND COALESCE(s.Qty,0)<>ol.RequestedQty)
) AS Violations;

-- Expected: 33 foreign keys, all enabled and trusted.
SELECT fk.name AS ForeignKeyName,
       OBJECT_NAME(fk.parent_object_id) AS ChildTable,
       OBJECT_NAME(fk.referenced_object_id) AS ParentTable,
       fk.is_disabled, fk.is_not_trusted
FROM sys.foreign_keys AS fk
WHERE OBJECT_SCHEMA_NAME(fk.parent_object_id) = N'dbo'
ORDER BY ChildTable, ForeignKeyName;
GO
