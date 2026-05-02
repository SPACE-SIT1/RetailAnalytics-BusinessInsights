/*==============================================================================
1. DATASET OVERVIEW
Goal: Understand the size, time coverage, and high-level business context of
the raw transaction table.
==============================================================================*/

-- 1.1 Total number of rows in the raw transactions table
SELECT
    COUNT(*) AS total_transaction_rows
FROM transactions;


-- 1.2 Date coverage and missing date count
SELECT
    MIN(DATE(date)) AS min_transaction_date,
    MAX(DATE(date)) AS max_transaction_date,
    COUNT(*) AS total_rows,
    SUM(CASE WHEN date IS NULL OR TRIM(date) IN ('', 'N/A', 'unknown') THEN 1 ELSE 0 END) AS missing_or_dirty_date_rows,
    ROUND(
        100.0 * SUM(CASE WHEN date IS NULL OR TRIM(date) IN ('', 'N/A', 'unknown') THEN 1 ELSE 0 END) / COUNT(*),
        2
    ) AS missing_or_dirty_date_pct
FROM transactions;


-- 1.3 Monthly transaction row count before cleaning
SELECT
    STRFTIME('%Y-%m', date) AS transaction_month,
    COUNT(*) AS row_count
FROM transactions
WHERE date IS NOT NULL
  AND TRIM(date) NOT IN ('', 'N/A', 'unknown')
GROUP BY STRFTIME('%Y-%m', date)
ORDER BY transaction_month;


-- 1.4 Raw distribution of transaction type
SELECT
    COALESCE(NULLIF(TRIM(transaction_type), ''), '[blank]') AS transaction_type,
    COUNT(*) AS row_count,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM transactions), 2) AS row_pct
FROM transactions
GROUP BY COALESCE(NULLIF(TRIM(transaction_type), ''), '[blank]')
ORDER BY row_count DESC;


-- 1.5 Raw distribution of payment method
SELECT
    COALESCE(NULLIF(TRIM(payment_method), ''), '[blank]') AS payment_method,
    COUNT(*) AS row_count,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM transactions), 2) AS row_pct
FROM transactions
GROUP BY COALESCE(NULLIF(TRIM(payment_method), ''), '[blank]')
ORDER BY row_count DESC;


/*==============================================================================
2. DATA STRUCTURE & KEY VARIABLES
Goal: Understand columns, data types, and business meaning of important fields.
==============================================================================*/

-- 2.1 Raw transactions table structure
SELECT
    cid AS ordinal_position,
    name AS column_name,
    type AS declared_type,
    CASE WHEN pk = 1 THEN 'YES' ELSE 'NO' END AS is_primary_key
FROM pragma_table_info('transactions')
ORDER BY cid;


-- 2.2 Key variables and business meaning
SELECT 'invoice_id' AS column_name, 'Invoice identifier; groups multiple product lines in one transaction' AS business_meaning
UNION ALL SELECT 'line_no', 'Line item number within an invoice'
UNION ALL SELECT 'customer_id', 'Customer identifier'
UNION ALL SELECT 'product_id', 'Product identifier'
UNION ALL SELECT 'sku', 'Stock keeping unit; may encode product, size, and color'
UNION ALL SELECT 'size', 'Purchased item size'
UNION ALL SELECT 'color', 'Purchased item color'
UNION ALL SELECT 'unit_price', 'Selling price per item unit'
UNION ALL SELECT 'quantity', 'Number of items purchased or returned'
UNION ALL SELECT 'discount', 'Discount rate applied to line item'
UNION ALL SELECT 'line_total', 'Line-level amount after discount'
UNION ALL SELECT 'invoice_total', 'Invoice-level total amount'
UNION ALL SELECT 'date', 'Transaction date and time'
UNION ALL SELECT 'transaction_type', 'Sale or Return'
UNION ALL SELECT 'payment_method', 'Payment channel used'
UNION ALL SELECT 'store_id', 'Store identifier'
UNION ALL SELECT 'employee_id', 'Employee identifier'
UNION ALL SELECT 'currency', 'Transaction currency'
UNION ALL SELECT 'currency_symbol', 'Currency symbol';


-- 2.3 Distinct count of major identifiers before cleaning
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT invoice_id) AS distinct_invoice_id,
    COUNT(DISTINCT customer_id) AS distinct_customer_id,
    COUNT(DISTINCT product_id) AS distinct_product_id,
    COUNT(DISTINCT sku) AS distinct_sku,
    COUNT(DISTINCT store_id) AS distinct_store_id,
    COUNT(DISTINCT employee_id) AS distinct_employee_id
FROM transactions;


/*==============================================================================
3. DATA QUALITY ASSESSMENT
Goal: Identify issues in raw transactions before cleaning.
==============================================================================*/


/*------------------------------------------------------------------------------
3.1 COMPLETENESS
Question: Which columns have missing or dirty placeholder values, and how much
data is affected?
------------------------------------------------------------------------------*/

-- 3.1.1 Missing / dirty value summary by column
SELECT 'invoice_id' AS column_name, 'identifier' AS column_type, COUNT(*) AS total_rows,
       SUM(CASE WHEN invoice_id IS NULL OR TRIM(invoice_id) IN ('', 'N/A', 'unknown') THEN 1 ELSE 0 END) AS missing_or_dirty_rows,
       ROUND(100.0 * SUM(CASE WHEN invoice_id IS NULL OR TRIM(invoice_id) IN ('', 'N/A', 'unknown') THEN 1 ELSE 0 END) / COUNT(*), 2) AS missing_or_dirty_pct
FROM transactions
UNION ALL SELECT 'line_no', 'numeric / identifier', COUNT(*),
       SUM(CASE WHEN line_no IS NULL OR TRIM(CAST(line_no AS TEXT)) IN ('', 'unknown') OR CAST(line_no AS REAL) = -1 THEN 1 ELSE 0 END),
       ROUND(100.0 * SUM(CASE WHEN line_no IS NULL OR TRIM(CAST(line_no AS TEXT)) IN ('', 'unknown') OR CAST(line_no AS REAL) = -1 THEN 1 ELSE 0 END) / COUNT(*), 2)
FROM transactions
UNION ALL SELECT 'customer_id', 'identifier', COUNT(*),
       SUM(CASE WHEN customer_id IS NULL OR TRIM(customer_id) IN ('', '-1', 'unknown', 'N/A') THEN 1 ELSE 0 END),
       ROUND(100.0 * SUM(CASE WHEN customer_id IS NULL OR TRIM(customer_id) IN ('', '-1', 'unknown', 'N/A') THEN 1 ELSE 0 END) / COUNT(*), 2)
FROM transactions
UNION ALL SELECT 'product_id', 'identifier', COUNT(*),
       SUM(CASE WHEN product_id IS NULL OR TRIM(product_id) IN ('', '-1', 'unknown', 'N/A') THEN 1 ELSE 0 END),
       ROUND(100.0 * SUM(CASE WHEN product_id IS NULL OR TRIM(product_id) IN ('', '-1', 'unknown', 'N/A') THEN 1 ELSE 0 END) / COUNT(*), 2)
FROM transactions
UNION ALL SELECT 'size', 'categorical', COUNT(*),
       SUM(CASE WHEN size IS NULL OR TRIM(size) IN ('', 'N/A', 'unknown') THEN 1 ELSE 0 END),
       ROUND(100.0 * SUM(CASE WHEN size IS NULL OR TRIM(size) IN ('', 'N/A', 'unknown') THEN 1 ELSE 0 END) / COUNT(*), 2)
FROM transactions
UNION ALL SELECT 'color', 'categorical', COUNT(*),
       SUM(CASE WHEN color IS NULL OR TRIM(color) IN ('', 'N/A', 'unknown') THEN 1 ELSE 0 END),
       ROUND(100.0 * SUM(CASE WHEN color IS NULL OR TRIM(color) IN ('', 'N/A', 'unknown') THEN 1 ELSE 0 END) / COUNT(*), 2)
FROM transactions
UNION ALL SELECT 'unit_price', 'numeric', COUNT(*),
       SUM(CASE WHEN unit_price IS NULL OR TRIM(CAST(unit_price AS TEXT)) IN ('', 'unknown') OR CAST(unit_price AS REAL) = -1 THEN 1 ELSE 0 END),
       ROUND(100.0 * SUM(CASE WHEN unit_price IS NULL OR TRIM(CAST(unit_price AS TEXT)) IN ('', 'unknown') OR CAST(unit_price AS REAL) = -1 THEN 1 ELSE 0 END) / COUNT(*), 2)
FROM transactions
UNION ALL SELECT 'quantity', 'numeric', COUNT(*),
       SUM(CASE WHEN quantity IS NULL OR TRIM(CAST(quantity AS TEXT)) IN ('', 'unknown') OR CAST(quantity AS REAL) = -1 THEN 1 ELSE 0 END),
       ROUND(100.0 * SUM(CASE WHEN quantity IS NULL OR TRIM(CAST(quantity AS TEXT)) IN ('', 'unknown') OR CAST(quantity AS REAL) = -1 THEN 1 ELSE 0 END) / COUNT(*), 2)
FROM transactions
UNION ALL SELECT 'date', 'datetime', COUNT(*),
       SUM(CASE WHEN date IS NULL OR TRIM(date) IN ('', 'N/A', 'unknown') THEN 1 ELSE 0 END),
       ROUND(100.0 * SUM(CASE WHEN date IS NULL OR TRIM(date) IN ('', 'N/A', 'unknown') THEN 1 ELSE 0 END) / COUNT(*), 2)
FROM transactions
UNION ALL SELECT 'discount', 'numeric', COUNT(*),
       SUM(CASE WHEN discount IS NULL OR TRIM(CAST(discount AS TEXT)) IN ('', 'unknown') OR CAST(discount AS REAL) = -1 THEN 1 ELSE 0 END),
       ROUND(100.0 * SUM(CASE WHEN discount IS NULL OR TRIM(CAST(discount AS TEXT)) IN ('', 'unknown') OR CAST(discount AS REAL) = -1 THEN 1 ELSE 0 END) / COUNT(*), 2)
FROM transactions
UNION ALL SELECT 'line_total', 'numeric', COUNT(*),
       SUM(CASE WHEN line_total IS NULL OR TRIM(CAST(line_total AS TEXT)) IN ('', 'unknown') OR CAST(line_total AS REAL) = -1 THEN 1 ELSE 0 END),
       ROUND(100.0 * SUM(CASE WHEN line_total IS NULL OR TRIM(CAST(line_total AS TEXT)) IN ('', 'unknown') OR CAST(line_total AS REAL) = -1 THEN 1 ELSE 0 END) / COUNT(*), 2)
FROM transactions
UNION ALL SELECT 'store_id', 'identifier', COUNT(*),
       SUM(CASE WHEN store_id IS NULL OR TRIM(store_id) IN ('', '-1', 'unknown', 'N/A') THEN 1 ELSE 0 END),
       ROUND(100.0 * SUM(CASE WHEN store_id IS NULL OR TRIM(store_id) IN ('', '-1', 'unknown', 'N/A') THEN 1 ELSE 0 END) / COUNT(*), 2)
FROM transactions
UNION ALL SELECT 'employee_id', 'identifier', COUNT(*),
       SUM(CASE WHEN employee_id IS NULL OR TRIM(employee_id) IN ('', '-1', 'unknown', 'N/A') THEN 1 ELSE 0 END),
       ROUND(100.0 * SUM(CASE WHEN employee_id IS NULL OR TRIM(employee_id) IN ('', '-1', 'unknown', 'N/A') THEN 1 ELSE 0 END) / COUNT(*), 2)
FROM transactions
UNION ALL SELECT 'currency', 'categorical', COUNT(*),
       SUM(CASE WHEN currency IS NULL OR TRIM(currency) IN ('', 'N/A', 'unknown') THEN 1 ELSE 0 END),
       ROUND(100.0 * SUM(CASE WHEN currency IS NULL OR TRIM(currency) IN ('', 'N/A', 'unknown') THEN 1 ELSE 0 END) / COUNT(*), 2)
FROM transactions
UNION ALL SELECT 'currency_symbol', 'categorical', COUNT(*),
       SUM(CASE WHEN currency_symbol IS NULL OR TRIM(currency_symbol) IN ('', 'N/A', 'unknown') THEN 1 ELSE 0 END),
       ROUND(100.0 * SUM(CASE WHEN currency_symbol IS NULL OR TRIM(currency_symbol) IN ('', 'N/A', 'unknown') THEN 1 ELSE 0 END) / COUNT(*), 2)
FROM transactions
UNION ALL SELECT 'sku', 'identifier / text', COUNT(*),
       SUM(CASE WHEN sku IS NULL OR TRIM(sku) IN ('', 'N/A', 'unknown') THEN 1 ELSE 0 END),
       ROUND(100.0 * SUM(CASE WHEN sku IS NULL OR TRIM(sku) IN ('', 'N/A', 'unknown') THEN 1 ELSE 0 END) / COUNT(*), 2)
FROM transactions
UNION ALL SELECT 'transaction_type', 'categorical', COUNT(*),
       SUM(CASE WHEN transaction_type IS NULL OR TRIM(transaction_type) IN ('', 'N/A', 'unknown') THEN 1 ELSE 0 END),
       ROUND(100.0 * SUM(CASE WHEN transaction_type IS NULL OR TRIM(transaction_type) IN ('', 'N/A', 'unknown') THEN 1 ELSE 0 END) / COUNT(*), 2)
FROM transactions
UNION ALL SELECT 'payment_method', 'categorical', COUNT(*),
       SUM(CASE WHEN payment_method IS NULL OR TRIM(payment_method) IN ('', 'N/A', 'unknown') THEN 1 ELSE 0 END),
       ROUND(100.0 * SUM(CASE WHEN payment_method IS NULL OR TRIM(payment_method) IN ('', 'N/A', 'unknown') THEN 1 ELSE 0 END) / COUNT(*), 2)
FROM transactions
UNION ALL SELECT 'invoice_total', 'numeric', COUNT(*),
       SUM(CASE WHEN invoice_total IS NULL OR TRIM(CAST(invoice_total AS TEXT)) IN ('', 'unknown') OR CAST(invoice_total AS REAL) = -1 THEN 1 ELSE 0 END),
       ROUND(100.0 * SUM(CASE WHEN invoice_total IS NULL OR TRIM(CAST(invoice_total AS TEXT)) IN ('', 'unknown') OR CAST(invoice_total AS REAL) = -1 THEN 1 ELSE 0 END) / COUNT(*), 2)
FROM transactions
ORDER BY missing_or_dirty_rows DESC;


-- 3.1.2 Breakdown of dirty placeholders by selected important columns
SELECT 'invoice_id' AS column_name, COALESCE(NULLIF(TRIM(invoice_id), ''), '[blank]') AS dirty_value, COUNT(*) AS row_count
FROM transactions
WHERE invoice_id IS NULL OR TRIM(invoice_id) IN ('', 'N/A', 'unknown')
GROUP BY COALESCE(NULLIF(TRIM(invoice_id), ''), '[blank]')
UNION ALL
SELECT 'customer_id', COALESCE(NULLIF(TRIM(customer_id), ''), '[blank]'), COUNT(*)
FROM transactions
WHERE customer_id IS NULL OR TRIM(customer_id) IN ('', '-1', 'unknown', 'N/A')
GROUP BY COALESCE(NULLIF(TRIM(customer_id), ''), '[blank]')
UNION ALL
SELECT 'product_id', COALESCE(NULLIF(TRIM(product_id), ''), '[blank]'), COUNT(*)
FROM transactions
WHERE product_id IS NULL OR TRIM(product_id) IN ('', '-1', 'unknown', 'N/A')
GROUP BY COALESCE(NULLIF(TRIM(product_id), ''), '[blank]')
UNION ALL
SELECT 'unit_price', COALESCE(NULLIF(TRIM(CAST(unit_price AS TEXT)), ''), '[blank]'), COUNT(*)
FROM transactions
WHERE unit_price IS NULL OR TRIM(CAST(unit_price AS TEXT)) IN ('', 'unknown') OR CAST(unit_price AS REAL) = -1
GROUP BY COALESCE(NULLIF(TRIM(CAST(unit_price AS TEXT)), ''), '[blank]')
UNION ALL
SELECT 'quantity', COALESCE(NULLIF(TRIM(CAST(quantity AS TEXT)), ''), '[blank]'), COUNT(*)
FROM transactions
WHERE quantity IS NULL OR TRIM(CAST(quantity AS TEXT)) IN ('', 'unknown') OR CAST(quantity AS REAL) = -1
GROUP BY COALESCE(NULLIF(TRIM(CAST(quantity AS TEXT)), ''), '[blank]')
UNION ALL
SELECT 'line_total', COALESCE(NULLIF(TRIM(CAST(line_total AS TEXT)), ''), '[blank]'), COUNT(*)
FROM transactions
WHERE line_total IS NULL OR TRIM(CAST(line_total AS TEXT)) IN ('', 'unknown') OR CAST(line_total AS REAL) = -1
GROUP BY COALESCE(NULLIF(TRIM(CAST(line_total AS TEXT)), ''), '[blank]')
UNION ALL
SELECT 'invoice_total', COALESCE(NULLIF(TRIM(CAST(invoice_total AS TEXT)), ''), '[blank]'), COUNT(*)
FROM transactions
WHERE invoice_total IS NULL OR TRIM(CAST(invoice_total AS TEXT)) IN ('', 'unknown') OR CAST(invoice_total AS REAL) = -1
GROUP BY COALESCE(NULLIF(TRIM(CAST(invoice_total AS TEXT)), ''), '[blank]')
ORDER BY column_name, row_count DESC;


/*------------------------------------------------------------------------------
3.2 ACCURACY
Question: Do financial values match expected business formulas?
------------------------------------------------------------------------------*/

-- 3.2.1 Check whether line_total matches unit_price * quantity * (1 - discount)
WITH normalized AS (
    SELECT
        CASE WHEN unit_price IS NULL OR TRIM(CAST(unit_price AS TEXT)) IN ('', 'unknown') OR CAST(unit_price AS REAL) = -1 THEN NULL ELSE CAST(unit_price AS REAL) END AS unit_price,
        CASE WHEN quantity IS NULL OR TRIM(CAST(quantity AS TEXT)) IN ('', 'unknown') OR CAST(quantity AS REAL) = -1 THEN NULL ELSE CAST(quantity AS REAL) END AS quantity,
        CASE WHEN discount IS NULL OR TRIM(CAST(discount AS TEXT)) IN ('', 'unknown') OR CAST(discount AS REAL) = -1 THEN NULL ELSE CAST(discount AS REAL) END AS discount,
        CASE WHEN line_total IS NULL OR TRIM(CAST(line_total AS TEXT)) IN ('', 'unknown') OR CAST(line_total AS REAL) = -1 THEN NULL ELSE CAST(line_total AS REAL) END AS line_total
    FROM transactions
)
SELECT
    COUNT(*) AS total_rows,
    SUM(CASE WHEN unit_price IS NULL OR quantity IS NULL OR discount IS NULL OR line_total IS NULL THEN 1 ELSE 0 END) AS rows_not_checkable_due_to_missing_values,
    SUM(CASE
            WHEN unit_price IS NOT NULL
             AND quantity IS NOT NULL
             AND discount IS NOT NULL
             AND line_total IS NOT NULL
             AND ABS(ABS(line_total) - ROUND(unit_price * quantity * (1 - discount), 2)) > 0.05
            THEN 1 ELSE 0
        END) AS possible_inaccurate_line_total_rows
FROM normalized;


-- 3.2.2 Check whether invoice_total matches SUM(line_total) per invoice
WITH normalized AS (
    SELECT
        invoice_id,
        CASE WHEN invoice_total IS NULL OR TRIM(CAST(invoice_total AS TEXT)) IN ('', 'unknown') OR CAST(invoice_total AS REAL) = -1 THEN NULL ELSE CAST(invoice_total AS REAL) END AS invoice_total,
        CASE WHEN line_total IS NULL OR TRIM(CAST(line_total AS TEXT)) IN ('', 'unknown') OR CAST(line_total AS REAL) = -1 THEN NULL ELSE CAST(line_total AS REAL) END AS line_total
    FROM transactions
    WHERE invoice_id IS NOT NULL
      AND TRIM(invoice_id) NOT IN ('', 'N/A', 'unknown')
),
invoice_check AS (
    SELECT
        invoice_id,
        MAX(invoice_total) AS invoice_total,
        ROUND(SUM(line_total), 2) AS sum_line_total,
        SUM(CASE WHEN line_total IS NULL THEN 1 ELSE 0 END) AS missing_line_total_rows
    FROM normalized
    GROUP BY invoice_id
)
SELECT
    COUNT(*) AS invoices_checked,
    SUM(CASE WHEN invoice_total IS NULL OR missing_line_total_rows > 0 THEN 1 ELSE 0 END) AS invoices_not_checkable_due_to_missing_values,
    SUM(CASE
            WHEN invoice_total IS NOT NULL
             AND missing_line_total_rows = 0
             AND ABS(invoice_total - sum_line_total) > 0.05
            THEN 1 ELSE 0
        END) AS possible_inaccurate_invoice_total_count
FROM invoice_check;


/*------------------------------------------------------------------------------
3.3 TIMELINESS
Question: Are date values available, parseable, and within a useful period?
------------------------------------------------------------------------------*/

-- 3.3.1 Date availability and parseability
SELECT
    COUNT(*) AS total_rows,
    MIN(DATE(date)) AS min_parseable_date,
    MAX(DATE(date)) AS max_parseable_date,
    SUM(CASE WHEN date IS NULL OR TRIM(date) IN ('', 'N/A', 'unknown') THEN 1 ELSE 0 END) AS missing_or_dirty_date_rows,
    SUM(CASE WHEN date IS NOT NULL AND TRIM(date) NOT IN ('', 'N/A', 'unknown') AND DATE(date) IS NULL THEN 1 ELSE 0 END) AS unparsable_date_rows
FROM transactions;


-- 3.3.2 Transaction row count by year
SELECT
    STRFTIME('%Y', date) AS transaction_year,
    COUNT(*) AS row_count
FROM transactions
WHERE date IS NOT NULL
  AND TRIM(date) NOT IN ('', 'N/A', 'unknown')
GROUP BY STRFTIME('%Y', date)
ORDER BY transaction_year;


/*------------------------------------------------------------------------------
3.4 CONSISTENCY
Question: Are values consistent within the same invoice?
------------------------------------------------------------------------------*/

-- 3.4.1 Invoice-level fields should normally be consistent within the same invoice
WITH normalized AS (
    SELECT
        invoice_id,
        CASE WHEN customer_id IS NULL OR TRIM(customer_id) IN ('', '-1', 'unknown', 'N/A') THEN NULL ELSE customer_id END AS customer_id,
        CASE WHEN store_id IS NULL OR TRIM(store_id) IN ('', '-1', 'unknown', 'N/A') THEN NULL ELSE store_id END AS store_id,
        CASE WHEN employee_id IS NULL OR TRIM(employee_id) IN ('', '-1', 'unknown', 'N/A') THEN NULL ELSE employee_id END AS employee_id,
        CASE WHEN date IS NULL OR TRIM(date) IN ('', 'N/A', 'unknown') THEN NULL ELSE date END AS transaction_datetime,
        CASE WHEN payment_method IS NULL OR TRIM(payment_method) IN ('', 'N/A', 'unknown') THEN NULL ELSE payment_method END AS payment_method,
        CASE WHEN invoice_total IS NULL OR TRIM(CAST(invoice_total AS TEXT)) IN ('', 'unknown') OR CAST(invoice_total AS REAL) = -1 THEN NULL ELSE CAST(invoice_total AS REAL) END AS invoice_total
    FROM transactions
    WHERE invoice_id IS NOT NULL
      AND TRIM(invoice_id) NOT IN ('', 'N/A', 'unknown')
),
invoice_profile AS (
    SELECT
        invoice_id,
        COUNT(DISTINCT customer_id) AS customer_count,
        COUNT(DISTINCT store_id) AS store_count,
        COUNT(DISTINCT employee_id) AS employee_count,
        COUNT(DISTINCT transaction_datetime) AS datetime_count,
        COUNT(DISTINCT payment_method) AS payment_method_count,
        COUNT(DISTINCT invoice_total) AS invoice_total_count
    FROM normalized
    GROUP BY invoice_id
)
SELECT
    COUNT(*) AS invoices_checked,
    SUM(CASE WHEN customer_count > 1 THEN 1 ELSE 0 END) AS invoices_with_multiple_customers,
    SUM(CASE WHEN store_count > 1 THEN 1 ELSE 0 END) AS invoices_with_multiple_stores,
    SUM(CASE WHEN employee_count > 1 THEN 1 ELSE 0 END) AS invoices_with_multiple_employees,
    SUM(CASE WHEN datetime_count > 1 THEN 1 ELSE 0 END) AS invoices_with_multiple_datetimes,
    SUM(CASE WHEN payment_method_count > 1 THEN 1 ELSE 0 END) AS invoices_with_multiple_payment_methods,
    SUM(CASE WHEN invoice_total_count > 1 THEN 1 ELSE 0 END) AS invoices_with_multiple_invoice_totals
FROM invoice_profile;


-- 3.4.2 Duplicate line numbers within invoice
SELECT
    invoice_id,
    line_no,
    COUNT(*) AS duplicate_rows
FROM transactions
WHERE invoice_id IS NOT NULL
  AND TRIM(invoice_id) NOT IN ('', 'N/A', 'unknown')
  AND line_no IS NOT NULL
GROUP BY invoice_id, line_no
HAVING COUNT(*) > 1
ORDER BY duplicate_rows DESC
LIMIT 50;


-- 3.4.3 Product_id missing while SKU is available
-- This indicates product_id may be recoverable from SKU during cleaning.
SELECT
    COUNT(*) AS total_rows,
    SUM(CASE WHEN product_id IS NULL OR TRIM(product_id) IN ('', '-1', 'unknown', 'N/A') THEN 1 ELSE 0 END) AS missing_product_id_rows,
    SUM(CASE
            WHEN (product_id IS NULL OR TRIM(product_id) IN ('', '-1', 'unknown', 'N/A'))
             AND sku IS NOT NULL
             AND TRIM(sku) NOT IN ('', 'N/A', 'unknown')
            THEN 1 ELSE 0
        END) AS missing_product_id_but_sku_available_rows
FROM transactions;


/*------------------------------------------------------------------------------
3.5 VALIDITY
Question: Do values follow expected domains and business rules?
------------------------------------------------------------------------------*/

-- 3.5.1 Invalid or unexpected domain values
SELECT 'transaction_type' AS field_name, COALESCE(NULLIF(TRIM(transaction_type), ''), '[blank]') AS invalid_value, COUNT(*) AS row_count
FROM transactions
WHERE transaction_type IS NULL
   OR TRIM(transaction_type) NOT IN ('Sale', 'Return')
GROUP BY COALESCE(NULLIF(TRIM(transaction_type), ''), '[blank]')
UNION ALL
SELECT 'payment_method', COALESCE(NULLIF(TRIM(payment_method), ''), '[blank]'), COUNT(*)
FROM transactions
WHERE payment_method IS NULL
   OR TRIM(payment_method) NOT IN ('Cash', 'Credit Card')
GROUP BY COALESCE(NULLIF(TRIM(payment_method), ''), '[blank]')
UNION ALL
SELECT 'currency', COALESCE(NULLIF(TRIM(currency), ''), '[blank]'), COUNT(*)
FROM transactions
WHERE currency IS NULL
   OR TRIM(currency) NOT IN ('USD')
GROUP BY COALESCE(NULLIF(TRIM(currency), ''), '[blank]')
UNION ALL
SELECT 'discount', COALESCE(NULLIF(TRIM(CAST(discount AS TEXT)), ''), '[blank]'), COUNT(*)
FROM transactions
WHERE discount IS NULL
   OR TRIM(CAST(discount AS TEXT)) IN ('', 'unknown')
   OR CAST(discount AS REAL) < 0
   OR CAST(discount AS REAL) > 1
GROUP BY COALESCE(NULLIF(TRIM(CAST(discount AS TEXT)), ''), '[blank]')
ORDER BY field_name, row_count DESC;


-- 3.5.2 Numeric validity checks
SELECT
    SUM(CASE WHEN unit_price IS NOT NULL AND TRIM(CAST(unit_price AS TEXT)) NOT IN ('', 'unknown') AND CAST(unit_price AS REAL) < 0 THEN 1 ELSE 0 END) AS negative_unit_price_rows,
    SUM(CASE WHEN quantity IS NOT NULL AND TRIM(CAST(quantity AS TEXT)) NOT IN ('', 'unknown') AND CAST(quantity AS REAL) <= 0 THEN 1 ELSE 0 END) AS non_positive_quantity_rows,
    SUM(CASE WHEN discount IS NOT NULL AND TRIM(CAST(discount AS TEXT)) NOT IN ('', 'unknown') AND (CAST(discount AS REAL) < 0 OR CAST(discount AS REAL) > 1) THEN 1 ELSE 0 END) AS invalid_discount_rows,
    SUM(CASE WHEN invoice_total IS NOT NULL AND TRIM(CAST(invoice_total AS TEXT)) NOT IN ('', 'unknown') AND CAST(invoice_total AS REAL) = -1 THEN 1 ELSE 0 END) AS invoice_total_placeholder_minus_one_rows
FROM transactions;
