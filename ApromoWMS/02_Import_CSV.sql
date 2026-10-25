/* Append this complete script to ApromoWMS_Assignment.sql.
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
INSERT INTO @Expected (LoadOrder, TableName, ExpectedRows) VALUES
(1, N'Supplier', 82),
(2, N'ProductCategory', 41),
(3, N'ProductGroup', 14),
(4, N'Product', 1008),
(5, N'ProductSupplier', 1008),
(6, N'Warehouse', 2),
(7, N'Worker', 5),
(8, N'StorageLocation', 4),
(9, N'Customer', 152),
(10, N'CustomerSite', 176),
(11, N'PurchaseOrder', 5),
(12, N'PurchaseOrderLine', 5),
(13, N'Receipt', 5),
(14, N'ReceiptLine', 5),
(15, N'InventoryLot', 5),
(16, N'ReceiptLineLot', 5),
(17, N'StockBalance', 5),
(18, N'TemperatureLog', 5),
(19, N'SalesOrder', 5),
(20, N'SalesOrderLine', 5),
(21, N'PickLine', 5),
(22, N'Shipment', 5),
(23, N'ShipmentLine', 3),
(24, N'ShipmentLineLot', 3);

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

    IF EXISTS (
        SELECT 1 FROM dbo.ReceiptLine rl JOIN dbo.Receipt r ON r.ReceiptID=rl.ReceiptID JOIN dbo.PurchaseOrderLine pl ON pl.PurchaseOrderLineID=rl.PurchaseOrderLineID WHERE r.PurchaseOrderID<>pl.PurchaseOrderID
    )
        THROW 51003, N'Receipt belongs to wrong purchase order', 1;

    IF EXISTS (
        SELECT 1 FROM dbo.ReceiptLineLot x JOIN dbo.ReceiptLine rl ON rl.ReceiptLineID=x.ReceiptLineID JOIN dbo.PurchaseOrderLine pl ON pl.PurchaseOrderLineID=rl.PurchaseOrderLineID JOIN dbo.InventoryLot l ON l.LotID=x.LotID WHERE pl.ProductID<>l.ProductID
    )
        THROW 51003, N'Receipt batch product mismatch', 1;

    IF EXISTS (
        SELECT 1 FROM dbo.ReceiptLine rl LEFT JOIN dbo.ReceiptLineLot x ON x.ReceiptLineID=rl.ReceiptLineID GROUP BY rl.ReceiptLineID,rl.ReceivedQty HAVING COALESCE(SUM(x.ReceivedQty),0)<>rl.ReceivedQty
    )
        THROW 51003, N'Receipt batch quantities do not sum to line quantity', 1;

    IF EXISTS (
        SELECT 1 FROM dbo.ShipmentLine sl JOIN dbo.Shipment s ON s.ShipmentID=sl.ShipmentID JOIN dbo.SalesOrderLine ol ON ol.SalesOrderLineID=sl.SalesOrderLineID WHERE s.SalesOrderID<>ol.SalesOrderID
    )
        THROW 51003, N'Shipment belongs to wrong sales order', 1;

    IF EXISTS (
        SELECT 1 FROM dbo.ShipmentLineLot x JOIN dbo.ShipmentLine sl ON sl.ShipmentLineID=x.ShipmentLineID JOIN dbo.SalesOrderLine ol ON ol.SalesOrderLineID=sl.SalesOrderLineID JOIN dbo.InventoryLot l ON l.LotID=x.LotID WHERE ol.ProductID<>l.ProductID
    )
        THROW 51003, N'Shipment batch product mismatch', 1;

    IF EXISTS (
        SELECT 1 FROM dbo.ShipmentLine sl LEFT JOIN dbo.ShipmentLineLot x ON x.ShipmentLineID=sl.ShipmentLineID GROUP BY sl.ShipmentLineID,sl.ShippedQty HAVING COALESCE(SUM(x.ShippedQty),0)<>sl.ShippedQty
    )
        THROW 51003, N'Shipment batch quantities do not sum to line quantity', 1;

    IF EXISTS (
        SELECT 1 FROM dbo.PickLine p JOIN dbo.SalesOrderLine ol ON ol.SalesOrderLineID=p.SalesOrderLineID JOIN dbo.StockBalance sb ON sb.StockBalanceID=p.StockBalanceID JOIN dbo.InventoryLot l ON l.LotID=sb.LotID WHERE l.ProductID<>ol.ProductID
    )
        THROW 51003, N'Pick batch product mismatch', 1;

    IF EXISTS (
        SELECT 1 FROM dbo.PickLine p JOIN dbo.Worker w ON w.WorkerID=p.WorkerID JOIN dbo.StockBalance sb ON sb.StockBalanceID=p.StockBalanceID JOIN dbo.StorageLocation loc ON loc.LocationID=sb.LocationID JOIN dbo.SalesOrderLine ol ON ol.SalesOrderLineID=p.SalesOrderLineID JOIN dbo.SalesOrder o ON o.SalesOrderID=ol.SalesOrderID WHERE w.WarehouseID<>o.WarehouseID OR loc.WarehouseID<>o.WarehouseID
    )
        THROW 51003, N'Pick warehouse mismatch', 1;

    IF EXISTS (
        SELECT 1 FROM dbo.Receipt r JOIN dbo.PurchaseOrder po ON po.PurchaseOrderID=r.PurchaseOrderID JOIN dbo.Worker w ON w.WorkerID=r.WorkerID WHERE w.WarehouseID<>po.WarehouseID
    )
        THROW 51003, N'Receipt warehouse mismatch', 1;

    IF EXISTS (
        SELECT 1 FROM dbo.PurchaseOrderLine pl JOIN dbo.PurchaseOrder po ON po.PurchaseOrderID=pl.PurchaseOrderID WHERE NOT EXISTS (SELECT 1 FROM dbo.ProductSupplier ps WHERE ps.ProductID=pl.ProductID AND ps.SupplierID=po.SupplierID)
    )
        THROW 51003, N'Purchase order supplier not linked to product', 1;

    IF EXISTS (
        SELECT 1 FROM dbo.InventoryLot l OUTER APPLY (SELECT SUM(x.ReceivedQty) AS Qty FROM dbo.ReceiptLineLot x WHERE x.LotID=l.LotID) r OUTER APPLY (SELECT SUM(x.ShippedQty) AS Qty FROM dbo.ShipmentLineLot x WHERE x.LotID=l.LotID) s OUTER APPLY (SELECT SUM(x.OnHandQty) AS Qty FROM dbo.StockBalance x WHERE x.LotID=l.LotID) b WHERE COALESCE(r.Qty,0)-COALESCE(s.Qty,0)<>COALESCE(b.Qty,0)
    )
        THROW 51003, N'Inventory does not reconcile to receipts minus shipments', 1;

    IF EXISTS (
        SELECT 1 FROM dbo.PurchaseOrderLine pl JOIN dbo.PurchaseOrder po ON po.PurchaseOrderID=pl.PurchaseOrderID OUTER APPLY (SELECT SUM(rl.ReceivedQty) AS Qty FROM dbo.ReceiptLine rl WHERE rl.PurchaseOrderLineID=pl.PurchaseOrderLineID) r WHERE COALESCE(r.Qty,0)>pl.OrderedQty OR (po.Status=N'Completed' AND COALESCE(r.Qty,0)<>pl.OrderedQty)
    )
        THROW 51003, N'Purchase order receipt quantity invalid', 1;

    IF EXISTS (
        SELECT 1 FROM dbo.SalesOrderLine ol JOIN dbo.SalesOrder o ON o.SalesOrderID=ol.SalesOrderID OUTER APPLY (SELECT SUM(sl.ShippedQty) AS Qty FROM dbo.ShipmentLine sl WHERE sl.SalesOrderLineID=ol.SalesOrderLineID) s WHERE COALESCE(s.Qty,0)>ol.RequestedQty OR (o.Status=N'Completed' AND COALESCE(s.Qty,0)<>ol.RequestedQty)
    )
        THROW 51003, N'Sales order shipment quantity invalid', 1;


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
