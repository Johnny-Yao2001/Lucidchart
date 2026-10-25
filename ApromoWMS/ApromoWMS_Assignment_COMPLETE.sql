/* COMPLETE ASSIGNMENT SCRIPT - FOR A NEW DATABASE ONLY.
The original uploaded schema is preserved below.
If tables already exist, DO NOT run this file from the beginning.
Run 02_Import_CSV.sql, then 04_Validate_Import.sql, then 03_DQL_Queries.sql.
CSV files must be available at the path configured in the import section.
Operational records are fictional test data, not real company transactions.
*/

USE master;
GO

IF DB_ID(N'ApromoWMS') IS NULL
BEGIN
    CREATE DATABASE ApromoWMS;
END;
GO

USE ApromoWMS;
GO

SELECT DB_NAME() AS CurrentDatabase;

/* Part 1 — WMS database design
   Step 1: Master tables and relationships
*/
USE ApromoWMS;
GO

SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    CREATE TABLE dbo.Supplier (
        SupplierID   int           NOT NULL,
        SupplierName nvarchar(150) NOT NULL,
        Website      nvarchar(255) NULL,
        Email        nvarchar(150) NULL,

        CONSTRAINT PK_Supplier
            PRIMARY KEY (SupplierID)
    );

    CREATE TABLE dbo.ProductCategory (
        CategoryID   int           NOT NULL,
        CategoryName nvarchar(100) NOT NULL,

        CONSTRAINT PK_ProductCategory
            PRIMARY KEY (CategoryID)
    );

    CREATE TABLE dbo.ProductGroup (
        ProductGroupID int           NOT NULL,
        GroupName      nvarchar(100) NOT NULL,
        ProductStream  nvarchar(50)  NOT NULL,

        CONSTRAINT PK_ProductGroup
            PRIMARY KEY (ProductGroupID)
    );

    CREATE TABLE dbo.Product (
        ProductID       int            NOT NULL,
        CategoryID      int            NOT NULL,
        ProductGroupID  int            NOT NULL,
        SourceProductID nvarchar(50)   NULL,
        Description     nvarchar(500)  NOT NULL,
        UnitOfMeasure   nvarchar(30)   NOT NULL,
        UnitPrice       decimal(12,2)  NULL,
        Discontinued    bit            NOT NULL,
        MinTempC        decimal(5,2)   NULL,
        MaxTempC        decimal(5,2)   NULL,
        GTIN            varchar(14)    NULL,

        CONSTRAINT PK_Product
            PRIMARY KEY (ProductID),

        CONSTRAINT FK_Product_Category
            FOREIGN KEY (CategoryID)
            REFERENCES dbo.ProductCategory (CategoryID),

        CONSTRAINT FK_Product_Group
            FOREIGN KEY (ProductGroupID)
            REFERENCES dbo.ProductGroup (ProductGroupID),

        CONSTRAINT CK_Product_UnitPrice
            CHECK (UnitPrice IS NULL OR UnitPrice >= 0),

        CONSTRAINT CK_Product_TemperatureRange
            CHECK (
                MinTempC IS NULL
                OR MaxTempC IS NULL
                OR MinTempC <= MaxTempC
            )
    );

    CREATE TABLE dbo.ProductSupplier (
        ProductSupplierID   int          NOT NULL,
        ProductID           int          NOT NULL,
        SupplierID          int          NOT NULL,
        SupplierProductCode nvarchar(50) NULL,
        IsPreferred         bit          NOT NULL,

        CONSTRAINT PK_ProductSupplier
            PRIMARY KEY (ProductSupplierID),

        CONSTRAINT FK_ProductSupplier_Product
            FOREIGN KEY (ProductID)
            REFERENCES dbo.Product (ProductID),

        CONSTRAINT FK_ProductSupplier_Supplier
            FOREIGN KEY (SupplierID)
            REFERENCES dbo.Supplier (SupplierID),

        CONSTRAINT UQ_ProductSupplier_Product_Supplier
            UNIQUE (ProductID, SupplierID)
    );

    CREATE TABLE dbo.Warehouse (
        WarehouseID   int           NOT NULL,
        WarehouseName nvarchar(100) NOT NULL,
        City          nvarchar(50)  NOT NULL,
        Address       nvarchar(255) NOT NULL,

        CONSTRAINT PK_Warehouse
            PRIMARY KEY (WarehouseID)
    );

    CREATE TABLE dbo.Worker (
        WorkerID       int           NOT NULL,
        WarehouseID    int           NOT NULL,
        WorkerName     nvarchar(100) NOT NULL,
        EmploymentType nvarchar(30)  NOT NULL,

        CONSTRAINT PK_Worker
            PRIMARY KEY (WorkerID),

        CONSTRAINT FK_Worker_Warehouse
            FOREIGN KEY (WarehouseID)
            REFERENCES dbo.Warehouse (WarehouseID)
    );

    CREATE TABLE dbo.StorageLocation (
        LocationID   int          NOT NULL,
        WarehouseID  int          NOT NULL,
        LocationCode nvarchar(50) NOT NULL,
        ZoneType     nvarchar(50) NOT NULL,
        MinTempC     decimal(5,2) NOT NULL,
        MaxTempC     decimal(5,2) NOT NULL,
        IsActive     bit          NOT NULL,

        CONSTRAINT PK_StorageLocation
            PRIMARY KEY (LocationID),

        CONSTRAINT FK_StorageLocation_Warehouse
            FOREIGN KEY (WarehouseID)
            REFERENCES dbo.Warehouse (WarehouseID),

        CONSTRAINT UQ_StorageLocation_Warehouse_Code
            UNIQUE (WarehouseID, LocationCode),

        CONSTRAINT CK_StorageLocation_TemperatureRange
            CHECK (MinTempC <= MaxTempC)
    );

    CREATE TABLE dbo.Customer (
        CustomerID   int           NOT NULL,
        CustomerName nvarchar(150) NOT NULL,
        CustomerType nvarchar(50)  NOT NULL,
        Description  nvarchar(1000) NULL,

        CONSTRAINT PK_Customer
            PRIMARY KEY (CustomerID)
    );

    CREATE TABLE dbo.CustomerSite (
        CustomerSiteID int           NOT NULL,
        CustomerID     int           NOT NULL,
        SiteName       nvarchar(150) NULL,
        Address        nvarchar(500) NULL,
        StateRegion    nvarchar(100) NULL,
        Postcode       nvarchar(20)  NULL,
        Country        nvarchar(100) NULL,
        Phone          nvarchar(100) NULL,
        Email          nvarchar(254) NULL,
        Website        nvarchar(500) NULL,

        CONSTRAINT PK_CustomerSite
            PRIMARY KEY (CustomerSiteID),

        CONSTRAINT FK_CustomerSite_Customer
            FOREIGN KEY (CustomerID)
            REFERENCES dbo.Customer (CustomerID)
    );

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO

-- Verify the ten master tables.
SELECT
    s.name AS SchemaName,
    t.name AS TableName
FROM sys.tables AS t
INNER JOIN sys.schemas AS s
    ON s.schema_id = t.schema_id
WHERE s.name = N'dbo'
  AND t.name IN (
      N'Supplier',
      N'ProductCategory',
      N'ProductGroup',
      N'Product',
      N'ProductSupplier',
      N'Warehouse',
      N'Worker',
      N'StorageLocation',
      N'Customer',
      N'CustomerSite'
  )
ORDER BY t.name;
GO

/* Part 1 — WMS database design
   Step 2: Transaction, inventory and temperature tables
*/
USE ApromoWMS;
GO

SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    CREATE TABLE dbo.PurchaseOrder (
        PurchaseOrderID int          NOT NULL,
        SupplierID      int          NOT NULL,
        WarehouseID     int          NOT NULL,
        OrderedAt       datetime2    NOT NULL,
        ExpectedAt      datetime2    NOT NULL,
        Status          nvarchar(30) NOT NULL,

        CONSTRAINT PK_PurchaseOrder
            PRIMARY KEY (PurchaseOrderID),

        CONSTRAINT FK_PurchaseOrder_Supplier
            FOREIGN KEY (SupplierID)
            REFERENCES dbo.Supplier (SupplierID),

        CONSTRAINT FK_PurchaseOrder_Warehouse
            FOREIGN KEY (WarehouseID)
            REFERENCES dbo.Warehouse (WarehouseID),

        CONSTRAINT CK_PurchaseOrder_Dates
            CHECK (ExpectedAt >= OrderedAt)
    );

    CREATE TABLE dbo.PurchaseOrderLine (
        PurchaseOrderLineID int           NOT NULL,
        PurchaseOrderID     int           NOT NULL,
        ProductID           int           NOT NULL,
        OrderedQty          decimal(12,2) NOT NULL,
        UnitCost            decimal(12,2) NOT NULL,

        CONSTRAINT PK_PurchaseOrderLine
            PRIMARY KEY (PurchaseOrderLineID),

        CONSTRAINT FK_PurchaseOrderLine_Order
            FOREIGN KEY (PurchaseOrderID)
            REFERENCES dbo.PurchaseOrder (PurchaseOrderID),

        CONSTRAINT FK_PurchaseOrderLine_Product
            FOREIGN KEY (ProductID)
            REFERENCES dbo.Product (ProductID),

        CONSTRAINT CK_PurchaseOrderLine_Quantity
            CHECK (OrderedQty > 0),

        CONSTRAINT CK_PurchaseOrderLine_Cost
            CHECK (UnitCost >= 0)
    );

    CREATE TABLE dbo.Receipt (
        ReceiptID       int          NOT NULL,
        PurchaseOrderID int          NOT NULL,
        WorkerID        int          NOT NULL,
        ReceivedAt      datetime2    NOT NULL,
        Status          nvarchar(30) NOT NULL,

        CONSTRAINT PK_Receipt
            PRIMARY KEY (ReceiptID),

        CONSTRAINT FK_Receipt_PurchaseOrder
            FOREIGN KEY (PurchaseOrderID)
            REFERENCES dbo.PurchaseOrder (PurchaseOrderID),

        CONSTRAINT FK_Receipt_Worker
            FOREIGN KEY (WorkerID)
            REFERENCES dbo.Worker (WorkerID)
    );

    CREATE TABLE dbo.ReceiptLine (
        ReceiptLineID       int           NOT NULL,
        ReceiptID           int           NOT NULL,
        PurchaseOrderLineID int           NOT NULL,
        ReceivedQty         decimal(12,2) NOT NULL,

        CONSTRAINT PK_ReceiptLine
            PRIMARY KEY (ReceiptLineID),

        CONSTRAINT FK_ReceiptLine_Receipt
            FOREIGN KEY (ReceiptID)
            REFERENCES dbo.Receipt (ReceiptID),

        CONSTRAINT FK_ReceiptLine_PurchaseOrderLine
            FOREIGN KEY (PurchaseOrderLineID)
            REFERENCES dbo.PurchaseOrderLine (PurchaseOrderLineID),

        CONSTRAINT CK_ReceiptLine_Quantity
            CHECK (ReceivedQty > 0)
    );

    CREATE TABLE dbo.InventoryLot (
        LotID      int          NOT NULL,
        ProductID  int          NOT NULL,
        LotCode    nvarchar(80) NOT NULL,
        ExpiryDate date         NULL,

        CONSTRAINT PK_InventoryLot
            PRIMARY KEY (LotID),

        CONSTRAINT FK_InventoryLot_Product
            FOREIGN KEY (ProductID)
            REFERENCES dbo.Product (ProductID),

        CONSTRAINT UQ_InventoryLot_Product_Code
            UNIQUE (ProductID, LotCode)
    );

    CREATE TABLE dbo.ReceiptLineLot (
        ReceiptLineLotID int           NOT NULL,
        ReceiptLineID    int           NOT NULL,
        LotID            int           NOT NULL,
        ReceivedQty      decimal(12,2) NOT NULL,

        CONSTRAINT PK_ReceiptLineLot
            PRIMARY KEY (ReceiptLineLotID),

        CONSTRAINT FK_ReceiptLineLot_ReceiptLine
            FOREIGN KEY (ReceiptLineID)
            REFERENCES dbo.ReceiptLine (ReceiptLineID),

        CONSTRAINT FK_ReceiptLineLot_Lot
            FOREIGN KEY (LotID)
            REFERENCES dbo.InventoryLot (LotID),

        CONSTRAINT UQ_ReceiptLineLot_Line_Lot
            UNIQUE (ReceiptLineID, LotID),

        CONSTRAINT CK_ReceiptLineLot_Quantity
            CHECK (ReceivedQty > 0)
    );

    CREATE TABLE dbo.StockBalance (
        StockBalanceID int           NOT NULL,
        LotID          int           NOT NULL,
        LocationID     int           NOT NULL,
        OnHandQty      decimal(12,2) NOT NULL,
        LastUpdatedAt  datetime2     NOT NULL,

        CONSTRAINT PK_StockBalance
            PRIMARY KEY (StockBalanceID),

        CONSTRAINT FK_StockBalance_Lot
            FOREIGN KEY (LotID)
            REFERENCES dbo.InventoryLot (LotID),

        CONSTRAINT FK_StockBalance_Location
            FOREIGN KEY (LocationID)
            REFERENCES dbo.StorageLocation (LocationID),

        CONSTRAINT UQ_StockBalance_Lot_Location
            UNIQUE (LotID, LocationID),

        CONSTRAINT CK_StockBalance_Quantity
            CHECK (OnHandQty >= 0)
    );

    CREATE TABLE dbo.TemperatureLog (
        TemperatureLogID int          NOT NULL,
        LocationID       int          NOT NULL,
        RecordedAt       datetime2    NOT NULL,
        TemperatureC     decimal(5,2) NOT NULL,

        CONSTRAINT PK_TemperatureLog
            PRIMARY KEY (TemperatureLogID),

        CONSTRAINT FK_TemperatureLog_Location
            FOREIGN KEY (LocationID)
            REFERENCES dbo.StorageLocation (LocationID)
    );

    CREATE TABLE dbo.SalesOrder (
        SalesOrderID       int          NOT NULL,
        CustomerSiteID     int          NOT NULL,
        WarehouseID        int          NOT NULL,
        OrderedAt          datetime2    NOT NULL,
        PromisedDeliveryAt datetime2    NOT NULL,
        Status             nvarchar(30) NOT NULL,

        CONSTRAINT PK_SalesOrder
            PRIMARY KEY (SalesOrderID),

        CONSTRAINT FK_SalesOrder_CustomerSite
            FOREIGN KEY (CustomerSiteID)
            REFERENCES dbo.CustomerSite (CustomerSiteID),

        CONSTRAINT FK_SalesOrder_Warehouse
            FOREIGN KEY (WarehouseID)
            REFERENCES dbo.Warehouse (WarehouseID),

        CONSTRAINT CK_SalesOrder_Dates
            CHECK (PromisedDeliveryAt >= OrderedAt)
    );

    CREATE TABLE dbo.SalesOrderLine (
        SalesOrderLineID int           NOT NULL,
        SalesOrderID     int           NOT NULL,
        ProductID        int           NOT NULL,
        RequestedQty     decimal(12,2) NOT NULL,

        CONSTRAINT PK_SalesOrderLine
            PRIMARY KEY (SalesOrderLineID),

        CONSTRAINT FK_SalesOrderLine_Order
            FOREIGN KEY (SalesOrderID)
            REFERENCES dbo.SalesOrder (SalesOrderID),

        CONSTRAINT FK_SalesOrderLine_Product
            FOREIGN KEY (ProductID)
            REFERENCES dbo.Product (ProductID),

        CONSTRAINT CK_SalesOrderLine_Quantity
            CHECK (RequestedQty > 0)
    );

    CREATE TABLE dbo.PickLine (
        PickLineID       int           NOT NULL,
        SalesOrderLineID int           NOT NULL,
        WorkerID         int           NOT NULL,
        StockBalanceID   int           NOT NULL,
        PickedQty        decimal(12,2) NOT NULL,
        CorrectQty       decimal(12,2) NULL,
        PickedAt         datetime2     NOT NULL,
        VerifiedAt       datetime2     NULL,

        CONSTRAINT PK_PickLine
            PRIMARY KEY (PickLineID),

        CONSTRAINT FK_PickLine_SalesOrderLine
            FOREIGN KEY (SalesOrderLineID)
            REFERENCES dbo.SalesOrderLine (SalesOrderLineID),

        CONSTRAINT FK_PickLine_Worker
            FOREIGN KEY (WorkerID)
            REFERENCES dbo.Worker (WorkerID),

        CONSTRAINT FK_PickLine_StockBalance
            FOREIGN KEY (StockBalanceID)
            REFERENCES dbo.StockBalance (StockBalanceID),

        CONSTRAINT CK_PickLine_PickedQty
            CHECK (PickedQty > 0),

        CONSTRAINT CK_PickLine_CorrectQty
            CHECK (
                CorrectQty IS NULL
                OR CorrectQty BETWEEN 0 AND PickedQty
            ),

        CONSTRAINT CK_PickLine_Verification
            CHECK (
                (
                    VerifiedAt IS NULL
                    AND CorrectQty IS NULL
                )
                OR
                (
                    VerifiedAt IS NOT NULL
                    AND CorrectQty IS NOT NULL
                    AND VerifiedAt >= PickedAt
                )
            )
    );

    CREATE TABLE dbo.Shipment (
        ShipmentID     int           NOT NULL,
        SalesOrderID   int           NOT NULL,
        DeliveryMethod nvarchar(30)  NOT NULL,
        CarrierName    nvarchar(100) NULL,
        DispatchedAt   datetime2     NULL,
        DeliveredAt    datetime2     NULL,
        DeliveryTempC  decimal(5,2)  NULL,

        CONSTRAINT PK_Shipment
            PRIMARY KEY (ShipmentID),

        CONSTRAINT FK_Shipment_SalesOrder
            FOREIGN KEY (SalesOrderID)
            REFERENCES dbo.SalesOrder (SalesOrderID),

        CONSTRAINT CK_Shipment_Dates
            CHECK (
                DeliveredAt IS NULL
                OR (
                    DispatchedAt IS NOT NULL
                    AND DeliveredAt >= DispatchedAt
                )
            )
    );

    CREATE TABLE dbo.ShipmentLine (
        ShipmentLineID   int           NOT NULL,
        ShipmentID       int           NOT NULL,
        SalesOrderLineID int           NOT NULL,
        ShippedQty       decimal(12,2) NOT NULL,

        CONSTRAINT PK_ShipmentLine
            PRIMARY KEY (ShipmentLineID),

        CONSTRAINT FK_ShipmentLine_Shipment
            FOREIGN KEY (ShipmentID)
            REFERENCES dbo.Shipment (ShipmentID),

        CONSTRAINT FK_ShipmentLine_SalesOrderLine
            FOREIGN KEY (SalesOrderLineID)
            REFERENCES dbo.SalesOrderLine (SalesOrderLineID),

        CONSTRAINT CK_ShipmentLine_Quantity
            CHECK (ShippedQty > 0)
    );

    CREATE TABLE dbo.ShipmentLineLot (
        ShipmentLineLotID int           NOT NULL,
        ShipmentLineID    int           NOT NULL,
        LotID             int           NOT NULL,
        ShippedQty        decimal(12,2) NOT NULL,

        CONSTRAINT PK_ShipmentLineLot
            PRIMARY KEY (ShipmentLineLotID),

        CONSTRAINT FK_ShipmentLineLot_ShipmentLine
            FOREIGN KEY (ShipmentLineID)
            REFERENCES dbo.ShipmentLine (ShipmentLineID),

        CONSTRAINT FK_ShipmentLineLot_Lot
            FOREIGN KEY (LotID)
            REFERENCES dbo.InventoryLot (LotID),

        CONSTRAINT UQ_ShipmentLineLot_Line_Lot
            UNIQUE (ShipmentLineID, LotID),

        CONSTRAINT CK_ShipmentLineLot_Quantity
            CHECK (ShippedQty > 0)
    );

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO

-- List all assignment tables.
SELECT
    s.name AS SchemaName,
    t.name AS TableName
FROM sys.tables AS t
INNER JOIN sys.schemas AS s
    ON s.schema_id = t.schema_id
WHERE s.name = N'dbo'
  AND t.is_ms_shipped = 0
  AND t.name <> N'sysdiagrams'
ORDER BY t.name;

-- Expected table count: 24.
SELECT COUNT(*) AS TableCount
FROM sys.tables AS t
INNER JOIN sys.schemas AS s
    ON s.schema_id = t.schema_id
WHERE s.name = N'dbo'
  AND t.is_ms_shipped = 0
  AND t.name <> N'sysdiagrams';
GO


/* ===== 02_Import_CSV.sql ===== */

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



/* ===== 04_Validate_Import.sql ===== */

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



/* ===== 03_DQL_Queries.sql ===== */

/* Part 2 - Four WMS monitoring queries.
   All operational data is fictional. Dates are FIXED for repeatable results.
   @EndDate is exclusive; @AsOf is inclusive.
   Only SELECT queries: this script does not modify data.
*/
USE ApromoWMS;
GO

/* Q1: Order picking accuracy.
   Primary metric: correct units / picked units among verified picks.
   Also report fully correct lines and unverified lines to expose metric limitations.
   VerifiedAt must be populated and no later than the reporting cutoff.
*/
DECLARE @StartDate datetime2 = '2026-03-01T00:00:00';
DECLARE @EndDate datetime2 = '2026-04-01T00:00:00';
DECLARE @AsOf datetime2 = '2026-03-12T12:00:00';

;WITH PickScope AS (
    SELECT p.PickLineID, p.PickedQty, p.CorrectQty,
           CASE WHEN p.VerifiedAt IS NOT NULL AND p.VerifiedAt <= @AsOf
                THEN 1 ELSE 0 END AS IsVerified
    FROM dbo.PickLine AS p
    WHERE p.PickedAt >= @StartDate
      AND p.PickedAt < @EndDate
      AND p.PickedAt <= @AsOf
), PickSummary AS (
    SELECT COUNT(*) AS TotalPickLines,
           COALESCE(SUM(IsVerified), 0) AS VerifiedPickLines,
           COALESCE(SUM(CASE WHEN IsVerified = 0 THEN 1 ELSE 0 END), 0) AS UnverifiedPickLines,
           COALESCE(SUM(CASE WHEN IsVerified = 1 THEN PickedQty ELSE 0 END), 0) AS VerifiedPickedQty,
           COALESCE(SUM(CASE WHEN IsVerified = 1 THEN CorrectQty ELSE 0 END), 0) AS VerifiedCorrectQty,
           COALESCE(SUM(CASE WHEN IsVerified = 1 AND CorrectQty = PickedQty THEN 1 ELSE 0 END), 0) AS FullyCorrectPickLines
    FROM PickScope
)
SELECT TotalPickLines, VerifiedPickLines, UnverifiedPickLines,
       VerifiedPickedQty, VerifiedCorrectQty,
       CAST(100.0 * VerifiedCorrectQty / NULLIF(VerifiedPickedQty, 0) AS decimal(6,2)) AS UnitPickingAccuracyPct,
       CAST(100.0 * FullyCorrectPickLines / NULLIF(VerifiedPickLines, 0) AS decimal(6,2)) AS FullyCorrectLinePct
FROM PickSummary;
GO

/* Q2: On-time shipments.
   Scope: shipment headers due in the reporting period, up to @AsOf.
   Include overdue undelivered shipments in the PRIMARY denominator.
   Delivered-only rate is shown separately; it can hide overdue pending work.
   A delivered partial shipment is not evidence of full order completion.
   Exclude cancelled sales orders. One planned header is counted as one shipment.
*/
DECLARE @StartDate datetime2 = '2026-03-01T00:00:00';
DECLARE @EndDate datetime2 = '2026-04-01T00:00:00';
DECLARE @AsOf datetime2 = '2026-03-12T12:00:00';

;WITH ShipmentScope AS (
    SELECT s.ShipmentID,
           CASE WHEN s.DeliveredAt IS NOT NULL AND s.DeliveredAt <= @AsOf
                THEN 1 ELSE 0 END AS IsDelivered,
           CASE WHEN s.DeliveredAt IS NOT NULL AND s.DeliveredAt <= @AsOf
                          AND s.DeliveredAt <= o.PromisedDeliveryAt
                THEN 1 ELSE 0 END AS IsOnTime
    FROM dbo.Shipment AS s
    INNER JOIN dbo.SalesOrder AS o ON o.SalesOrderID = s.SalesOrderID
    WHERE o.PromisedDeliveryAt >= @StartDate
      AND o.PromisedDeliveryAt < @EndDate
      AND o.PromisedDeliveryAt <= @AsOf
      AND o.Status <> N'Cancelled'
), ShipmentSummary AS (
    SELECT COUNT(*) AS DueShipments,
           COALESCE(SUM(IsDelivered), 0) AS DeliveredShipments,
           COALESCE(SUM(IsOnTime), 0) AS OnTimeDeliveredShipments
    FROM ShipmentScope
)
SELECT DueShipments, DeliveredShipments, OnTimeDeliveredShipments,
       DueShipments - DeliveredShipments AS OverdueUndeliveredShipments,
       CAST(100.0 * OnTimeDeliveredShipments / NULLIF(DueShipments, 0) AS decimal(6,2)) AS DueShipmentOnTimePct,
       CAST(100.0 * OnTimeDeliveredShipments / NULLIF(DeliveredShipments, 0) AS decimal(6,2)) AS DeliveredOnlyOnTimePct
FROM ShipmentSummary;
GO

/* Q3: On-time receipts from suppliers.
   Scope: non-cancelled purchase orders due by @AsOf in the reporting period.
   Require ALL order lines to be received in full, not only a first partial receipt.
   Aggregate receipts to order-line level first to prevent join multiplication.
   Primary denominator includes overdue incomplete purchase orders.
   Latest receipt time is the completion time under the fixture's no-overreceipt policy.
*/
DECLARE @StartDate datetime2 = '2026-03-01T00:00:00';
DECLARE @EndDate datetime2 = '2026-04-01T00:00:00';
DECLARE @AsOf datetime2 = '2026-03-12T12:00:00';

;WITH LineReceipts AS (
    SELECT rl.PurchaseOrderLineID,
           SUM(rl.ReceivedQty) AS ReceivedQty,
           MAX(r.ReceivedAt) AS LastReceivedAt
    FROM dbo.ReceiptLine AS rl
    INNER JOIN dbo.Receipt AS r ON r.ReceiptID = rl.ReceiptID
    WHERE r.Status = N'Completed'
      AND r.ReceivedAt <= @AsOf
    GROUP BY rl.PurchaseOrderLineID
), OrderReceiptStatus AS (
    SELECT po.PurchaseOrderID, po.SupplierID, po.ExpectedAt,
           MIN(CASE WHEN COALESCE(lr.ReceivedQty, 0) >= pl.OrderedQty
                    THEN 1 ELSE 0 END) AS IsFullyReceived,
           MAX(lr.LastReceivedAt) AS CompletedAt
    FROM dbo.PurchaseOrder AS po
    INNER JOIN dbo.PurchaseOrderLine AS pl ON pl.PurchaseOrderID = po.PurchaseOrderID
    LEFT JOIN LineReceipts AS lr ON lr.PurchaseOrderLineID = pl.PurchaseOrderLineID
    WHERE po.ExpectedAt >= @StartDate
      AND po.ExpectedAt < @EndDate
      AND po.ExpectedAt <= @AsOf
      AND po.Status <> N'Cancelled'
    GROUP BY po.PurchaseOrderID, po.SupplierID, po.ExpectedAt
), SupplierSummary AS (
    SELECT SupplierID,
           COUNT(*) AS DuePurchaseOrders,
           SUM(IsFullyReceived) AS FullyReceivedOrders,
           SUM(CASE WHEN IsFullyReceived = 1 AND CompletedAt <= ExpectedAt
                    THEN 1 ELSE 0 END) AS OnTimeFullyReceivedOrders
    FROM OrderReceiptStatus
    GROUP BY SupplierID
)
SELECT s.SupplierID, s.SupplierName,
       ss.DuePurchaseOrders, ss.FullyReceivedOrders, ss.OnTimeFullyReceivedOrders,
       ss.DuePurchaseOrders - ss.FullyReceivedOrders AS OverdueIncompleteOrders,
       CAST(100.0 * ss.OnTimeFullyReceivedOrders / NULLIF(ss.DuePurchaseOrders, 0) AS decimal(6,2)) AS DueOrderOnTimeReceiptPct,
       CAST(100.0 * ss.OnTimeFullyReceivedOrders / NULLIF(ss.FullyReceivedOrders, 0) AS decimal(6,2)) AS CompletedOnlyOnTimeReceiptPct
FROM SupplierSummary AS ss
INNER JOIN dbo.Supplier AS s ON s.SupplierID = ss.SupplierID
ORDER BY s.SupplierID;
GO

/* Q4: Warehouse capacity used (current snapshot).
   Assignment definition: occupied storage locations / total storage locations.
   Count each location once even if it holds multiple lots; include empty locations.
   Operational policy: inactive locations are excluded from usable capacity.
   This is a CURRENT SNAPSHOT, not a historical time average.
   StockBalance has no historical snapshots; a period average cannot be inferred.
*/
;WITH OccupiedLocations AS (
    SELECT LocationID
    FROM dbo.StockBalance
    WHERE OnHandQty > 0
    GROUP BY LocationID
)
SELECT w.WarehouseID, w.WarehouseName,
       COUNT(l.LocationID) AS ActiveStorageLocations,
       COUNT(o.LocationID) AS OccupiedStorageLocations,
       COUNT(l.LocationID) - COUNT(o.LocationID) AS EmptyStorageLocations,
       CAST(100.0 * COUNT(o.LocationID) / NULLIF(COUNT(l.LocationID), 0) AS decimal(6,2)) AS CurrentCapacityUsedPct
FROM dbo.Warehouse AS w
LEFT JOIN dbo.StorageLocation AS l
    ON l.WarehouseID = w.WarehouseID AND l.IsActive = 1
LEFT JOIN OccupiedLocations AS o ON o.LocationID = l.LocationID
GROUP BY w.WarehouseID, w.WarehouseName
ORDER BY w.WarehouseID;
GO
