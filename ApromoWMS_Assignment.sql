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