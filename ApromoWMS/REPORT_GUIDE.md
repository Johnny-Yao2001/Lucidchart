# Report preparation notes

These notes explain implementation choices. Write the analysis in your own words and cite your actual sources and AI conversation if used. Fixture outputs are not evidence that SQL Server has executed successfully.

## Part 1: Design reasoning

- Customer / CustomerSite: separate organization identity from delivery addresses. Source customer grouping remains provisional.
- ProductCategory / ProductGroup: distinguish categories from worksheet/stream grouping. Product uses an internal key because source IDs are missing or duplicated.
- ProductSupplier: supports multiple suppliers per product without repeating product descriptions; current data does not establish verified multiple suppliers for a canonical SKU.
- PurchaseOrder / PurchaseOrderLine and SalesOrder / SalesOrderLine: separate order dates and parties from product quantities; support multi-line orders.
- Receipt / ReceiptLine / ReceiptLineLot: allow partial receipts and link each receipt line to batches.
- Shipment / ShipmentLine / ShipmentLineLot: support partial shipments and batch traceability for recalls. A delivery timestamp alone does not establish full order fulfilment.
- InventoryLot / StockBalance / StorageLocation: separate batch identity from quantity and location. One batch can occupy several locations; a location can hold several batches.
- Worker: attributes receipt and picking activity; the simple schema assigns one current warehouse per worker, without historical transfers.
- TemperatureLog and Shipment.DeliveryTempC: support storage and delivery monitoring, but do not establish HACCP certification. Actual product-specific temperature requirements are unknown.
- PK/FK, UNIQUE and CHECK constraints protect identity, references and domain rules. Cross-table checks remain necessary: a foreign key alone does not establish that a picked lot contains the ordered product.

Limitations: no complete stock-movement ledger, historical stock snapshots, certification-document management, immutable audit trail, stock reservations, put-away task timestamps or physical counts. Describe this as a coursework prototype, not a production-certified WMS.

## Part 2: Query analysis

All operational data is fictional and dates are fixed to March 2026. Do not use GETDATE() to filter these fixtures.

| Query | Expected main result | Analysis |
|---|---|---|
| Q1 picking accuracy | 48/50 verified units = 96.00%; 1 unverified line | Quantity weighting differs from fully correct line accuracy (3/4 = 75.00%). Unverified work is neither a confirmed success nor an error. Large lines dominate weighted rates. |
| Q2 on-time shipments | 2/4 due shipments = 50.00%; 1 overdue undelivered | Delivered-only rate is 2/3 = 66.67%, which hides pending overdue work. A shipment can be a partial order, so this is not full order completion or OTIF. Promise date is inherited from the order. Orders without shipment headers require a separate backlog check. |
| Q3 supplier receipts | 3/5 due purchase orders = 60.00%; 1 overdue incomplete | Require every line to be fully received. Aggregate receipts first to avoid join multiplication. Completed-only rate is 3/4 = 75.00%, which excludes overdue partial receipts. Latest receipt is a completion proxy under the fixture's no-overreceipt policy; excess receipts/corrections require a cumulative quantity calculation. |
| Q4 capacity used | Sydney 2/2 = 100.00%; Melbourne 1/2 = 50.00% | Count locations, not lots; include empty locations. Inactive locations are excluded as an explicit usable-capacity policy. This is a snapshot, not a historical period average or a cubic-volume measure. |

Q4 addresses the assignment concern called “Average warehouse capacity used” using its stated occupied-location ratio. Explain the snapshot limitation: a historical time average requires inventory history. Do not call a single snapshot a measured time average.

Five fictional operational cases demonstrate logic, not actual supplier or employee performance.

## Windows evidence and completion steps

1. Run 02_Import_CSV.sql after the 24 empty tables exist; save IMPORT PASSED.
2. Run 04_Validate_Import.sql. All 24 counts must match, all 13 business checks must have IssueCount=0, and all 33 FKs must be enabled and trusted.
3. Execute each Q1-Q4 batch in 03_DQL_Queries.sql separately. Include its DECLARE statements when selecting it. Capture both SQL and actual results in each screenshot.
4. SSMS: ApromoWMS > Database Diagrams > right-click > New Database Diagram. Accept diagram support objects if prompted. Add the 24 application tables (not sysdiagrams), arrange and save. This has not been done by cloud tools on your Windows database.
5. Capture a diagram overview and readable detail views as needed. Label initial Lucidchart and final SSMS diagrams distinctly.
6. Keep setup, CSV load and DQL commands in one submitted .sql file. ApromoWMS_Assignment_COMPLETE.sql combines them for a NEW database. Your database already has tables: run only import, validation and query sections, not CREATE TABLE again.
7. Retain source Excel, CSV, cleaning log and mapping. Confirm final upload requirements in the course portal.

## AI assistance disclosure

Explain actual ChatGPT assistance with schema translation, profiling, CSV transformations, dummy-data generation and SQL drafting. Describe your verification and changes, especially duplicate source codes, overdue denominators, partial receipts and snapshot limitations. Cite the actual conversation webpage using the course's reference style. AI-generated sample outputs do not replace SSMS execution evidence.
