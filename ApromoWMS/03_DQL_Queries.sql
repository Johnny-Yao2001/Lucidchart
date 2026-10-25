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
