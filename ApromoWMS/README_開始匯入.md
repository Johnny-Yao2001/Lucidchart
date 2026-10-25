# ApromoWMS CSV 匯入包

此包適用於對話中已建立的 24 張資料表。保留你原本的建庫、建表 SQL。
原始 Excel 未修改。這些資料是作業開發資料，不能視為經核實的 Apromo 實際營運資料。

## Windows 操作

1. 將 ZIP 內的內容解壓縮到 `C:\ApromoWMS`。
2. 確認檔案位置是 `C:\ApromoWMS\csv\Product.csv`，不是多包一層資料夾。
3. 不要用 Excel 開啟後另存這些 CSV，以免變更前導零、日期、編碼或換行。
4. 在 SSMS 開啟 `C:\ApromoWMS\02_Import_CSV.sql`。
5. 檢查 SQL 中 `@CsvFolder`，預設為 `C:\ApromoWMS\csv\`。若使用其他位置，修改這個變數，保留最後的反斜線。
6. 確認連線仍是你建立 ApromoWMS 的 SQL Server Express，按 F5 執行這份匯入腳本。
7. 成功結果應為 `IMPORT PASSED`、`TablesLoaded=24`，以及 24 張表各自的核對筆數。外鍵預期 33 個，DisabledOrUntrusted 應為 0。
8. 成功後，把匯入腳本全文加到你保留的 `ApromoWMS_Assignment.sql` 最下方並儲存。只需保存，不要重新執行已完成的建表或匯入區段。

## 失敗時

- 任何目標表已經有資料：腳本會停止，不刪除或覆蓋既有資料。
- 檔案找不到（Operating system error code 3）：確認解壓縮位置、檔名及 @CsvFolder。
- Access denied（Operating system error code 5）：需要讓 SQL Server 的服務帳戶有該資料夾的讀取權限。你能從桌面看到檔案，不代表服務帳戶能讀取。不要授予 Everyone 完全控制。
- Bulk-load permission error：需確認目前 SQL Server 登入帳戶的匯入權限。
- 任一匯入或資料驗證失敗：交易會回復本次新增資料。保留 Messages 中完整錯誤，以便診斷。
- 不要為了匯入而停用外鍵、刪除資料表或重複執行整份作業腳本。

## 包含的檔案

- `csv/`：24 張資料表各自的 UTF-8 CSV（LF 換行），第一列是欄位名，順序與已建立的資料表一致。
- `02_Import_CSV.sql`：按相依順序匯入，檢查實際筆數、外鍵狀態及跨表商業規則。非空表會阻止匯入。
- `03_DQL_Queries.sql`：四個正式 SELECT 查詢，包含日期期間、計算定義及限制。
- `04_Validate_Import.sql`：匯入後可重複執行的唯讀驗證，列出實際筆數、跨表問題數及外鍵狀態。
- `ApromoWMS_Assignment_COMPLETE.sql`：原始建庫／建表與後續步驟的合併版，供作業整理；已有資料表的資料庫不能從頭重跑。
- `REPORT_GUIDE.md`：設計理由、查詢評析重點，以及 SSMS 圖與截圖操作。
- `audit/cleaning_log.csv`：清理、補值、衝突及待確認項目。
- `audit/source_mapping.csv`：產品與客戶據點的來源列至內部 ID 對應。
- `audit/source_rows.json`：來源資料列的原始儲存值備份（Excel 格式與樣式仍應參考原檔）。
- `audit/manifest.json`：來源雜湊、每表筆數及測試資料的預期指標。
- `audit/local_validation.json`：本機資料驗證結果，與尚未執行的 SQL Server 驗證分開列示。
- `audit/query_logic_validation.json`：使用 SQLite 執行查詢邏輯及五個邊界案例的結果；不能作為 SQL Server 已執行的證明。
- `prepare_data.py`、`build_import.py`、`schema_columns.json`：可重現轉換與驗證的輔助檔。Windows 匯入不需要執行 Python，也不需要安裝 Python。

## 重要資料處理假設（報告可討論，不能當成已核實事實）

1. 1,008 筆來源產品列皆保留，各自配置內部 ProductID。54 組原始產品編號出現重複；暫以獨立產品記錄保留，待人工判定真實產品身分。此決策避免資料遺失，但可能高估實際 SKU 數，不應宣稱已完成產品主檔去重。
2. 28 筆來源產品沒有原始編號，SourceProductID 保持 NULL。沒有捏造原始編號。
3. 分類缺漏時以工作表名稱補值。ProductGroup 表示工作表群組；ProductStream 表示 Retail 或 Ingredients and Food Service。分類字詞保留原文，未擅自合併拼法相近的分類。
4. UnitOfMeasure='Source pack' 是統一測試假設：一單位代表該 Excel 描述的一個來源包裝，不拆成克、公斤或單顆。UnitPrice 沿用來源值，未核實幣別、包裝定價或不同列價格衝突。
5. 供應商僅按清理空白後的名稱完全相符分組；未擅自合併疑似別名。網站僅檢查格式，缺少 scheme 時補 https://，同一供應商多個 URL 時暫取第一個格式有效值；網站真實性未驗證。SupplierProductCode 留 NULL，未假設來源 Product ID 就是供應商自有編號。
6. 176 筆客戶據點保留；只有名稱（不分大小寫）及網站 hostname 同時相符才暫歸同一 Customer（152 筆）。沒有網站時不依名稱自動合併。此規則仍需人工確認，不保證企業身分相同。CustomerType 暫取第一筆來源類型，多元角色需後續設計處理。
7. 國家／地區主要由工作表名稱推定。New Zealand 工作表內的可疑地理與電話資料已記錄，不能當成已核實地址。僅擷取明確州別後的四碼澳洲郵遞區號，模糊者留 NULL。
8. 無效 email 留 NULL；若明確是 URL 且 Website 缺漏，移至 Website。無法解析的 Website 留 NULL。Fax 沒有對應欄位，保留於 raw audit。未連線查核任何聯絡資訊。
9. 產品實際溫度範圍、GTIN、效期未在來源提供，產品欄位保持 NULL。示範儲位 15–20°C 與示範配送溫度純屬虛構，不能當成食品安全標準。TemperatureLog 的 22°C 紀錄是故意設計的超溫測試案例，不代表匯入錯誤。
10. Sydney 與 Melbourne 各 2 個示範儲位，作為等容量的簡化模型；並非真實倉庫儲位數。

## 虛構營運資料與預期結果

營運日期固定於 2026 年 3 月，資料快照為 `2026-03-12T12:00:00`。後續查詢應使用明確期間，不能直接以今天日期篩選而導致零筆結果。

Warehouse、Worker、StorageLocation 及所有採購、收貨、批次、庫存、溫度、銷售、揀貨、出貨資料皆為測試資料。它們連結真實來源產品／客戶主檔，但不代表這些交易實際發生。缺資料的表皆先建立不超過 5 筆資料；兩張出貨明細表各 3 筆。

- 5 張採購單：4 張完整收貨，其中 3 張準時、1 張延遲；另 1 張只收 40/100，保持未完成。只看已完成採購單時，準時率應為 75.00%；此分母會排除逾期未完成單，需在分析中說明。
- 5 張銷售單／5 個 shipment headers：3 個已送達 shipment，2 個準時、1 個延遲；另外 2 個為尚未派送的計畫，不建立出貨明細。其中延遲送達單僅出貨 18/20，訂單狀態為 Partially Delivered，不能當作整張訂單已完成。
- 若按已送達 shipment 計算準時率，預期是 66.67%，這並非全訂單完整準時履行率。未完成、逾期及分批送貨的處理，應在最終指標定義中清楚交代。
- 5 筆揀貨：4 筆已驗證，PickedQty 合計 50，CorrectQty 合計 48。以數量加權且排除未驗證紀錄時，準確率為 96.00%。此結果不同於「完全正確揀貨列數／已驗證列數」（75.00%），應標明採用哪一種定義。
- 揀貨代表取出／預留，仍屬 OnHand；只有出貨才扣減目前庫存，未建立額外預留庫存欄位。
- Sydney 有庫存儲位 2/2（100.00%）；Melbourne 1/2（50.00%）。同一儲位多個批次只計一次。空儲位即使沒有 StockBalance 列，也要列入分母。此資料只能證明當時使用率；沒有歷史快照，不能計算期間平均使用率。
- 庫存核對假設：期初庫存為 0，沒有調整、退貨、報廢或轉倉；每批次目前庫存＝收貨批次數量−出貨批次數量。此簡化假設不代表完整生產級 WMS。

## 已完成與尚未完成的驗證

已在雲端本機驗證 24 份 CSV 的欄位、型別、長度、必填值、PK、唯一鍵、33 個 FK 關係及跨表數量一致性，並確認驗證程式能拒絕五類故意造出的錯誤案例。CSV 可重現。

已備妥四個正式 DQL 查詢，並用 SQLite 做獨立邏輯測試。嘗試啟動雲端 SQL Server 時，官方映像層的下載站 centralus.data.mcr.microsoft.com 被網路代理回傳 403，未能啟動 SQL Server。尚未在你的 Windows SQL Server Express 執行 BULK INSERT、四個查詢及 SSMS 圖。這個包是匯入與查詢用資料，不是已完成的作業。

你的 SQL Server 服務帳戶權限、檔案存取、CSV 解析與 T-SQL 執行結果，必須以 SSMS 實際輸出確認。取得 IMPORT PASSED 後，再進行正式查詢、SSMS Diagram 與報告截圖。
