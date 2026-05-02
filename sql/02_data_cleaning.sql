-- Sale analytics cleaning script for SQLite
-- This script keeps the original raw tables unchanged and creates a clean layer.

DROP VIEW IF EXISTS v_transactions_clean;

CREATE VIEW v_transactions_clean AS
SELECT
    CASE
        WHEN invoice_id IS NULL OR TRIM(invoice_id) IN ('', 'N/A', 'unknown') THEN NULL
        ELSE TRIM(invoice_id)
    END AS invoice_id,

    CASE
        WHEN line_no IS NULL OR TRIM(CAST(line_no AS TEXT)) IN ('', 'unknown') OR CAST(line_no AS REAL) = -1 THEN NULL
        ELSE CAST(line_no AS INTEGER)
    END AS line_no,

    CASE
        WHEN customer_id IS NULL OR TRIM(customer_id) IN ('', '-1', 'unknown', 'N/A') THEN NULL
        ELSE TRIM(customer_id)
    END AS customer_id,

    CASE
        WHEN product_id IS NULL OR TRIM(product_id) IN ('', '-1', 'unknown', 'N/A') THEN NULL
        ELSE TRIM(product_id)
    END AS product_id,

    CASE
        WHEN size IS NULL OR TRIM(size) IN ('', 'N/A', 'unknown') THEN NULL
        ELSE TRIM(size)
    END AS size,

    CASE
        WHEN color IS NULL OR TRIM(color) IN ('', 'N/A', 'unknown') THEN NULL
        ELSE TRIM(color)
    END AS color,

    CASE
        WHEN unit_price IS NULL OR TRIM(CAST(unit_price AS TEXT)) IN ('', 'unknown') OR CAST(unit_price AS REAL) = -1 THEN NULL
        ELSE CAST(unit_price AS REAL)
    END AS unit_price,

    CASE
        WHEN quantity IS NULL OR TRIM(CAST(quantity AS TEXT)) IN ('', 'unknown') OR CAST(quantity AS REAL) = -1 THEN NULL
        ELSE CAST(quantity AS INTEGER)
    END AS quantity,

    CASE
        WHEN date IS NULL OR TRIM(date) IN ('', 'N/A', 'unknown') THEN NULL
        ELSE TRIM(date)
    END AS transaction_datetime,

    DATE(
        CASE
            WHEN date IS NULL OR TRIM(date) IN ('', 'N/A', 'unknown') THEN NULL
            ELSE TRIM(date)
        END
    ) AS transaction_date,

    CASE
        WHEN discount IS NULL OR TRIM(CAST(discount AS TEXT)) IN ('', 'unknown') OR CAST(discount AS REAL) = -1 THEN NULL
        ELSE CAST(discount AS REAL)
    END AS discount,

    CASE
        WHEN line_total IS NULL OR TRIM(CAST(line_total AS TEXT)) IN ('', 'unknown') OR CAST(line_total AS REAL) = -1 THEN NULL
        ELSE CAST(line_total AS REAL)
    END AS line_total_raw,

    CASE
        WHEN store_id IS NULL OR TRIM(store_id) IN ('', '-1', 'unknown', 'N/A') THEN NULL
        ELSE TRIM(store_id)
    END AS store_id,

    CASE
        WHEN employee_id IS NULL OR TRIM(employee_id) IN ('', '-1', 'unknown', 'N/A') THEN NULL
        ELSE TRIM(employee_id)
    END AS employee_id,

    CASE
        WHEN currency IS NULL OR TRIM(currency) IN ('', 'N/A', 'unknown') THEN 'USD'
        ELSE TRIM(currency)
    END AS currency,

    CASE
        WHEN currency_symbol IS NULL OR TRIM(currency_symbol) IN ('', 'N/A', 'unknown') THEN '$'
        ELSE TRIM(currency_symbol)
    END AS currency_symbol,

    CASE
        WHEN sku IS NULL OR TRIM(sku) IN ('', 'N/A', 'unknown') THEN NULL
        ELSE TRIM(sku)
    END AS sku,

    CASE
        WHEN transaction_type IS NULL OR TRIM(transaction_type) IN ('', 'N/A', 'unknown') THEN NULL
        ELSE TRIM(transaction_type)
    END AS transaction_type,

    CASE
        WHEN payment_method IS NULL OR TRIM(payment_method) IN ('', 'N/A', 'unknown') THEN NULL
        ELSE TRIM(payment_method)
    END AS payment_method,

    CASE
        WHEN invoice_total IS NULL OR TRIM(CAST(invoice_total AS TEXT)) IN ('', 'unknown') OR CAST(invoice_total AS REAL) = -1 THEN NULL
        ELSE CAST(invoice_total AS REAL)
    END AS invoice_total,

    CASE
        WHEN invoice_id IS NULL OR TRIM(invoice_id) IN ('', 'N/A', 'unknown') THEN 1
        WHEN date IS NULL OR TRIM(date) IN ('', 'N/A', 'unknown') THEN 1
        WHEN unit_price IS NULL OR TRIM(CAST(unit_price AS TEXT)) IN ('', 'unknown') OR CAST(unit_price AS REAL) = -1 THEN 1
        WHEN quantity IS NULL OR TRIM(CAST(quantity AS TEXT)) IN ('', 'unknown') OR CAST(quantity AS REAL) = -1 THEN 1
        WHEN transaction_type IS NULL OR TRIM(transaction_type) IN ('', 'N/A', 'unknown') THEN 1
        ELSE 0
    END AS has_critical_issue
FROM transactions;

DROP TABLE IF EXISTS transactions_clean;

CREATE TABLE transactions_clean AS
SELECT
    invoice_id,
    line_no,
    COALESCE(customer_id, 'UNKNOWN_CUSTOMER') AS customer_id,
    product_id,
    size,
    color,
    unit_price,
    quantity,
    transaction_datetime,
    transaction_date,
    discount,
    ROUND(
        COALESCE(
            line_total_raw,
            unit_price * quantity * (1 - COALESCE(discount, 0))
        ),
        2
    ) AS line_total,
    store_id,
    employee_id,
    currency,
    currency_symbol,
    sku,
    transaction_type,
    payment_method,
    invoice_total
FROM v_transactions_clean
WHERE has_critical_issue = 0;

DROP TABLE IF EXISTS transactions_rejected;

CREATE TABLE transactions_rejected AS
SELECT *
FROM v_transactions_clean
WHERE has_critical_issue = 1;

DROP VIEW IF EXISTS v_invalid_foreign_keys;

CREATE VIEW v_invalid_foreign_keys AS
SELECT 'customer_id' AS field, t.customer_id AS invalid_value, COUNT(*) AS cnt
FROM transactions_clean t
LEFT JOIN customers c
    ON t.customer_id = c.customer_id
WHERE t.customer_id IS NOT NULL
  AND c.customer_id IS NULL
GROUP BY t.customer_id

UNION ALL

SELECT 'product_id', t.product_id, COUNT(*)
FROM transactions_clean t
LEFT JOIN products p
    ON t.product_id = p.product_id
WHERE t.product_id IS NOT NULL
  AND p.product_id IS NULL
GROUP BY t.product_id

UNION ALL

SELECT 'store_id', t.store_id, COUNT(*)
FROM transactions_clean t
LEFT JOIN stores s
    ON t.store_id = s.store_id
WHERE t.store_id IS NOT NULL
  AND s.store_id IS NULL
GROUP BY t.store_id

UNION ALL

SELECT 'employee_id', t.employee_id, COUNT(*)
FROM transactions_clean t
LEFT JOIN employees e
    ON t.employee_id = e.employee_id
WHERE t.employee_id IS NOT NULL
  AND e.employee_id IS NULL
GROUP BY t.employee_id;

DROP TABLE IF EXISTS transactions_imputed;

CREATE TABLE transactions_imputed AS
WITH RECURSIVE normalized AS (
    SELECT
        rowid AS source_rowid,
        CASE
            WHEN invoice_id IS NULL OR TRIM(invoice_id) IN ('', 'N/A', 'unknown') THEN NULL
            ELSE TRIM(invoice_id)
        END AS invoice_id,
        CASE
            WHEN line_no IS NULL OR TRIM(CAST(line_no AS TEXT)) IN ('', 'unknown') OR CAST(line_no AS REAL) = -1 THEN NULL
            ELSE CAST(line_no AS INTEGER)
        END AS line_no,
        CASE
            WHEN customer_id IS NULL OR TRIM(customer_id) IN ('', '-1', 'unknown', 'N/A') THEN NULL
            ELSE TRIM(customer_id)
        END AS customer_id,
        CASE
            WHEN product_id IS NULL OR TRIM(product_id) IN ('', '-1', 'unknown', 'N/A') THEN NULL
            ELSE TRIM(product_id)
        END AS product_id,
        CASE
            WHEN size IS NULL OR TRIM(size) IN ('', 'N/A', 'unknown') THEN NULL
            ELSE TRIM(size)
        END AS size,
        CASE
            WHEN color IS NULL OR TRIM(color) IN ('', 'N/A', 'unknown') THEN NULL
            ELSE TRIM(color)
        END AS color,
        CASE
            WHEN unit_price IS NULL OR TRIM(CAST(unit_price AS TEXT)) IN ('', 'unknown') OR CAST(unit_price AS REAL) = -1 THEN NULL
            ELSE CAST(unit_price AS REAL)
        END AS unit_price,
        CASE
            WHEN quantity IS NULL OR TRIM(CAST(quantity AS TEXT)) IN ('', 'unknown') OR CAST(quantity AS REAL) = -1 THEN NULL
            ELSE CAST(quantity AS INTEGER)
        END AS quantity,
        CASE
            WHEN date IS NULL OR TRIM(date) IN ('', 'N/A', 'unknown') THEN NULL
            ELSE TRIM(date)
        END AS transaction_datetime,
        CASE
            WHEN discount IS NULL OR TRIM(CAST(discount AS TEXT)) IN ('', 'unknown') OR CAST(discount AS REAL) = -1 THEN NULL
            ELSE CAST(discount AS REAL)
        END AS discount,
        CASE
            WHEN line_total IS NULL OR TRIM(CAST(line_total AS TEXT)) IN ('', 'unknown') OR CAST(line_total AS REAL) = -1 THEN NULL
            ELSE CAST(line_total AS REAL)
        END AS line_total,
        CASE
            WHEN store_id IS NULL OR TRIM(store_id) IN ('', '-1', 'unknown', 'N/A') THEN NULL
            ELSE TRIM(store_id)
        END AS store_id,
        CASE
            WHEN employee_id IS NULL OR TRIM(employee_id) IN ('', '-1', 'unknown', 'N/A') THEN NULL
            ELSE TRIM(employee_id)
        END AS employee_id,
        CASE
            WHEN currency IS NULL OR TRIM(currency) IN ('', 'N/A', 'unknown') THEN NULL
            ELSE TRIM(currency)
        END AS currency,
        CASE
            WHEN currency_symbol IS NULL OR TRIM(currency_symbol) IN ('', 'N/A', 'unknown') THEN NULL
            ELSE TRIM(currency_symbol)
        END AS currency_symbol,
        CASE
            WHEN sku IS NULL OR TRIM(sku) IN ('', 'N/A', 'unknown') THEN NULL
            ELSE TRIM(sku)
        END AS sku,
        CASE
            WHEN transaction_type IS NULL OR TRIM(transaction_type) IN ('', 'N/A', 'unknown') THEN NULL
            ELSE TRIM(transaction_type)
        END AS transaction_type,
        CASE
            WHEN payment_method IS NULL OR TRIM(payment_method) IN ('', 'N/A', 'unknown') THEN NULL
            ELSE TRIM(payment_method)
        END AS payment_method,
        CASE
            WHEN invoice_total IS NULL OR TRIM(CAST(invoice_total AS TEXT)) IN ('', 'unknown') OR CAST(invoice_total AS REAL) = -1 THEN NULL
            ELSE CAST(invoice_total AS REAL)
        END AS invoice_total
    FROM transactions
),
invoice_stats AS (
    SELECT
        invoice_id,
        COUNT(DISTINCT customer_id) AS customer_dist,
        MAX(customer_id) AS customer_fill,
        COUNT(DISTINCT transaction_datetime) AS datetime_dist,
        MAX(transaction_datetime) AS datetime_fill,
        COUNT(DISTINCT store_id) AS store_dist,
        MAX(store_id) AS store_fill,
        COUNT(DISTINCT employee_id) AS employee_dist,
        MAX(employee_id) AS employee_fill,
        COUNT(DISTINCT currency) AS currency_dist,
        MAX(currency) AS currency_fill,
        COUNT(DISTINCT currency_symbol) AS symbol_dist,
        MAX(currency_symbol) AS symbol_fill,
        COUNT(DISTINCT transaction_type) AS type_dist,
        MAX(transaction_type) AS type_fill,
        COUNT(DISTINCT payment_method) AS payment_dist,
        MAX(payment_method) AS payment_fill,
        COUNT(DISTINCT invoice_total) AS total_dist,
        MAX(invoice_total) AS total_fill
    FROM normalized
    WHERE invoice_id IS NOT NULL
    GROUP BY invoice_id
),
price_mode AS (
    SELECT product_id, unit_price
    FROM (
        SELECT
            product_id,
            unit_price,
            COUNT(*) AS price_count,
            ROW_NUMBER() OVER (
                PARTITION BY product_id
                ORDER BY COUNT(*) DESC, unit_price DESC
            ) AS price_rank
        FROM normalized
        WHERE product_id IS NOT NULL
          AND unit_price IS NOT NULL
        GROUP BY product_id, unit_price
    )
    WHERE price_rank = 1
),
quantity_mode AS (
    SELECT product_id, quantity
    FROM (
        SELECT
            product_id,
            quantity,
            COUNT(*) AS quantity_count,
            ROW_NUMBER() OVER (
                PARTITION BY product_id
                ORDER BY COUNT(*) DESC, quantity ASC
            ) AS quantity_rank
        FROM normalized
        WHERE product_id IS NOT NULL
          AND quantity IS NOT NULL
          AND quantity > 0
        GROUP BY product_id, quantity
    )
    WHERE quantity_rank = 1
),
global_quantity_mode AS (
    SELECT quantity
    FROM (
        SELECT
            quantity,
            COUNT(*) AS quantity_count,
            ROW_NUMBER() OVER (
                ORDER BY COUNT(*) DESC, quantity ASC
            ) AS quantity_rank
        FROM normalized
        WHERE quantity IS NOT NULL
          AND quantity > 0
        GROUP BY quantity
    )
    WHERE quantity_rank = 1
),
sku_chars AS (
    SELECT
        n.source_rowid,
        n.sku,
        1 AS pos,
        substr(n.sku, 1, 1) AS ch
    FROM normalized n
    WHERE n.product_id IS NULL
      AND n.sku IS NOT NULL

    UNION ALL

    SELECT
        source_rowid,
        sku,
        pos + 1,
        substr(sku, pos + 1, 1)
    FROM sku_chars
    WHERE pos < length(sku)
),
sku_first_digit AS (
    SELECT
        source_rowid,
        sku,
        MIN(pos) AS first_digit_pos
    FROM sku_chars
    WHERE ch BETWEEN '0' AND '9'
    GROUP BY source_rowid, sku
),
sku_digit_bounds AS (
    SELECT
        f.source_rowid,
        f.sku,
        f.first_digit_pos,
        COALESCE(
            MIN(c.pos),
            length(f.sku) + 1
        ) AS first_after_digits_pos
    FROM sku_first_digit f
    LEFT JOIN sku_chars c
        ON f.source_rowid = c.source_rowid
       AND c.pos > f.first_digit_pos
       AND c.ch NOT BETWEEN '0' AND '9'
    GROUP BY f.source_rowid, f.sku, f.first_digit_pos
),
sku_product AS (
    SELECT
        b.source_rowid,
        substr(
            b.sku,
            b.first_digit_pos,
            b.first_after_digits_pos - b.first_digit_pos
        ) AS product_id
    FROM sku_digit_bounds b
    JOIN products p
        ON substr(
            b.sku,
            b.first_digit_pos,
            b.first_after_digits_pos - b.first_digit_pos
        ) = p.product_id
),
invoice_customer AS (
    SELECT
        invoice_id,
        COUNT(DISTINCT customer_id) AS customer_dist,
        MAX(customer_id) AS customer_fill
    FROM normalized
    WHERE invoice_id IS NOT NULL
      AND customer_id IS NOT NULL
    GROUP BY invoice_id
),
invoice_ranked AS (
    SELECT
        n.*,
        i.customer_dist,
        i.customer_fill,
        i.datetime_dist,
        i.datetime_fill,
        i.store_dist,
        i.store_fill,
        i.employee_dist,
        i.employee_fill,
        i.currency_dist,
        i.currency_fill,
        i.symbol_dist,
        i.symbol_fill,
        i.type_dist,
        i.type_fill,
        i.payment_dist,
        i.payment_fill,
        i.total_dist,
        i.total_fill,
        ROW_NUMBER() OVER (
            PARTITION BY n.invoice_id
            ORDER BY n.source_rowid
        ) AS invoice_row_number
    FROM normalized n
    LEFT JOIN invoice_stats i
        ON n.invoice_id = i.invoice_id
),
filled_base AS (
    SELECT
        r.source_rowid,
        r.invoice_id,
        COALESCE(r.line_no, CASE WHEN r.invoice_id IS NOT NULL THEN r.invoice_row_number END) AS line_no,
        COALESCE(
            r.customer_id,
            CASE WHEN r.customer_dist = 1 THEN r.customer_fill END,
            CASE WHEN rc.customer_dist = 1 THEN rc.customer_fill END
        ) AS customer_id,
        COALESCE(r.product_id, sp.product_id) AS product_id,
        r.size AS size,
        COALESCE(r.color, p.color) AS color,
        r.unit_price,
        r.quantity,
        COALESCE(r.transaction_datetime, CASE WHEN r.datetime_dist = 1 THEN r.datetime_fill END) AS transaction_datetime,
        r.discount,
        r.line_total,
        COALESCE(
            r.store_id,
            CASE WHEN r.store_dist = 1 THEN r.store_fill END,
            e.store_id
        ) AS store_id,
        COALESCE(r.employee_id, CASE WHEN r.employee_dist = 1 THEN r.employee_fill END) AS employee_id,
        COALESCE(r.currency, CASE WHEN r.currency_dist = 1 THEN r.currency_fill END, 'USD') AS currency,
        COALESCE(r.currency_symbol, CASE WHEN r.symbol_dist = 1 THEN r.symbol_fill END, '$') AS currency_symbol,
        r.sku,
        COALESCE(r.transaction_type, CASE WHEN r.type_dist = 1 THEN r.type_fill END) AS transaction_type,
        COALESCE(r.payment_method, CASE WHEN r.payment_dist = 1 THEN r.payment_fill END) AS payment_method,
        COALESCE(r.invoice_total, CASE WHEN r.total_dist = 1 THEN r.total_fill END) AS invoice_total,
        pm.unit_price AS product_mode_unit_price,
        qm.quantity AS product_mode_quantity,
        gqm.quantity AS global_mode_quantity
    FROM invoice_ranked r
    LEFT JOIN sku_product sp
        ON r.source_rowid = sp.source_rowid
    LEFT JOIN invoice_customer rc
        ON r.invoice_id LIKE 'RET-%'
       AND rc.invoice_id = 'INV-' || substr(r.invoice_id, 5)
    LEFT JOIN products p
        ON COALESCE(r.product_id, sp.product_id) = p.product_id
    LEFT JOIN employees e
        ON COALESCE(r.employee_id, CASE WHEN r.employee_dist = 1 THEN r.employee_fill END) = e.employee_id
    LEFT JOIN price_mode pm
        ON COALESCE(r.product_id, sp.product_id) = pm.product_id
    LEFT JOIN quantity_mode qm
        ON COALESCE(r.product_id, sp.product_id) = qm.product_id
    CROSS JOIN global_quantity_mode gqm
),
calculated AS (
    SELECT
        *,
        CASE
            WHEN unit_price IS NULL
             AND line_total IS NOT NULL
             AND quantity IS NOT NULL
             AND discount IS NOT NULL
             AND quantity <> 0
             AND (1 - discount) <> 0
            THEN ROUND(ABS(line_total) / (quantity * (1 - discount)), 2)
        END AS unit_price_from_formula,
        CASE
            WHEN quantity IS NULL
             AND line_total IS NOT NULL
             AND unit_price IS NOT NULL
             AND discount IS NOT NULL
             AND unit_price <> 0
             AND (1 - discount) <> 0
             AND ABS(
                ABS(line_total) / (unit_price * (1 - discount))
                - ROUND(ABS(line_total) / (unit_price * (1 - discount)))
             ) < 0.01
            THEN CAST(ROUND(ABS(line_total) / (unit_price * (1 - discount))) AS INTEGER)
        END AS quantity_from_formula,
        CASE
            WHEN discount IS NULL
             AND line_total IS NOT NULL
             AND unit_price IS NOT NULL
             AND quantity IS NOT NULL
             AND unit_price <> 0
             AND quantity <> 0
             AND 1 - ABS(line_total) / (unit_price * quantity) BETWEEN 0 AND 1
            THEN ROUND(1 - ABS(line_total) / (unit_price * quantity), 4)
        END AS discount_from_formula
    FROM filled_base
),
final_lines AS (
    SELECT
        source_rowid,
        invoice_id,
        line_no,
        customer_id,
        product_id,
        COALESCE(size, 'Unknown') AS size,
        COALESCE(color, 'Not specified') AS color,
        COALESCE(unit_price, unit_price_from_formula, product_mode_unit_price) AS unit_price,
        COALESCE(quantity, quantity_from_formula, product_mode_quantity, global_mode_quantity) AS quantity,
        transaction_datetime,
        DATE(transaction_datetime) AS transaction_date,
        COALESCE(discount, discount_from_formula, 0) AS discount,
        store_id,
        employee_id,
        currency,
        currency_symbol,
        sku,
        transaction_type,
        payment_method,
        invoice_total,
        line_total,
        unit_price_from_formula,
        product_mode_unit_price,
        product_mode_quantity,
        global_mode_quantity,
        quantity_from_formula,
        discount_from_formula
    FROM calculated
),
line_stage AS (
    SELECT
        *,
        ROUND(
            COALESCE(
                line_total,
                CASE
                    WHEN unit_price IS NOT NULL
                     AND quantity IS NOT NULL
                    THEN
                        CASE
                            WHEN transaction_type = 'Return'
                            THEN -1 * unit_price * quantity * (1 - discount)
                            ELSE unit_price * quantity * (1 - discount)
                        END
                END
            ),
            2
        ) AS line_total_stage
    FROM final_lines
),
invoice_line_stats AS (
    SELECT
        invoice_id,
        COUNT(*) AS invoice_line_count,
        SUM(CASE WHEN line_total_stage IS NULL THEN 1 ELSE 0 END) AS missing_line_total_count,
        SUM(COALESCE(line_total_stage, 0)) AS known_line_total_sum,
        COUNT(DISTINCT invoice_total) AS invoice_total_dist,
        MAX(invoice_total) AS invoice_total_fill
    FROM line_stage
    WHERE invoice_id IS NOT NULL
    GROUP BY invoice_id
),
residual_filled AS (
    SELECT
        l.*,
        CASE
            WHEN l.line_total_stage IS NULL
             AND s.missing_line_total_count = 1
             AND s.invoice_total_dist = 1
             AND s.invoice_total_fill IS NOT NULL
            THEN ROUND(s.invoice_total_fill - s.known_line_total_sum, 2)
        END AS line_total_from_invoice_residual
    FROM line_stage l
    LEFT JOIN invoice_line_stats s
        ON l.invoice_id = s.invoice_id
),
final_total_stats AS (
    SELECT
        invoice_id,
        SUM(
            CASE
                WHEN COALESCE(line_total_stage, line_total_from_invoice_residual) IS NULL THEN 1
                ELSE 0
            END
        ) AS final_missing_line_total_count,
        ROUND(
            SUM(COALESCE(line_total_stage, line_total_from_invoice_residual)),
            2
        ) AS final_sum_line_total
    FROM residual_filled
    GROUP BY invoice_id
),
final_ready AS (
    SELECT
        r.*,
        f.final_missing_line_total_count,
        f.final_sum_line_total
    FROM residual_filled r
    LEFT JOIN final_total_stats f
        ON r.invoice_id = f.invoice_id
)
SELECT
    source_rowid,
    invoice_id,
    line_no,
    COALESCE(customer_id, 'UNKNOWN_CUSTOMER') AS customer_id,
    product_id,
    size,
    color,
    unit_price,
    COALESCE(
        quantity,
        CASE
            WHEN line_total_from_invoice_residual IS NOT NULL
             AND unit_price IS NOT NULL
             AND discount IS NOT NULL
             AND unit_price <> 0
             AND (1 - discount) <> 0
             AND ABS(
                ABS(line_total_from_invoice_residual) / (unit_price * (1 - discount))
                - ROUND(ABS(line_total_from_invoice_residual) / (unit_price * (1 - discount)))
             ) < 0.01
            THEN CAST(ROUND(ABS(line_total_from_invoice_residual) / (unit_price * (1 - discount))) AS INTEGER)
        END
    ) AS quantity,
    transaction_datetime,
    transaction_date,
    discount,
    COALESCE(line_total_stage, line_total_from_invoice_residual) AS line_total,
    store_id,
    COALESCE(employee_id, 'UNKNOWN_STORE_' || COALESCE(store_id, 'UNKNOWN')) AS employee_id,
    currency,
    currency_symbol,
    COALESCE(sku, 'Not available') AS sku,
    transaction_type,
    COALESCE(payment_method, 'Unknown') AS payment_method,
    COALESCE(
        invoice_total,
        CASE
            WHEN final_missing_line_total_count = 0 THEN final_sum_line_total
        END
    ) AS invoice_total,
    CASE WHEN line_no IS NOT NULL THEN 1 ELSE 0 END AS has_line_no,
    CASE WHEN customer_id IS NOT NULL THEN 1 ELSE 0 END AS has_customer_id,
    CASE WHEN product_id IS NOT NULL THEN 1 ELSE 0 END AS has_product_id,
    CASE WHEN unit_price IS NOT NULL THEN 1 ELSE 0 END AS has_unit_price,
    CASE
        WHEN quantity IS NOT NULL OR line_total_from_invoice_residual IS NOT NULL THEN 1
        ELSE 0
    END AS has_quantity
FROM final_ready
WHERE invoice_id IS NOT NULL
  AND transaction_datetime IS NOT NULL
  AND transaction_type IS NOT NULL;

DROP TABLE IF EXISTS employees_final;

CREATE TABLE employees_final AS
SELECT
    employee_id,
    store_id,
    name,
    position
FROM employees

UNION ALL

SELECT
    'UNKNOWN_STORE_' || store_id AS employee_id,
    store_id,
    'Unknown Employee - Store ' || store_id AS name,
    'Unknown' AS position
FROM stores

UNION ALL

SELECT
    'UNKNOWN_STORE_UNKNOWN' AS employee_id,
    NULL AS store_id,
    'Unknown Employee - Unknown Store' AS name,
    'Unknown' AS position;

DROP TABLE IF EXISTS customers_final;

CREATE TABLE customers_final AS
SELECT
    customer_id,
    name,
    email,
    telephone,
    city,
    country,
    gender,
    date_of_birth,
    job_title
FROM customers

UNION ALL

SELECT
    'UNKNOWN_CUSTOMER' AS customer_id,
    'Unknown Customer' AS name,
    'Unknown' AS email,
    'Unknown' AS telephone,
    'Unknown' AS city,
    'Unknown' AS country,
    'Unknown' AS gender,
    NULL AS date_of_birth,
    'Unknown' AS job_title;

DROP TABLE IF EXISTS products_final;

CREATE TABLE products_final AS
SELECT
    product_id,
    category,
    sub_category,
    description_pt,
    description_de,
    description_fr,
    description_es,
    description_en,
    description_zh,
    COALESCE(color, 'Not specified') AS color,
    COALESCE(size, 'Unknown') AS size,
    production_cost
FROM products

UNION ALL

SELECT
    'UNKNOWN_PRODUCT' AS product_id,
    'Unknown' AS category,
    'Unknown' AS sub_category,
    'Unknown' AS description_pt,
    'Unknown' AS description_de,
    'Unknown' AS description_fr,
    'Unknown' AS description_es,
    'Unknown' AS description_en,
    'Unknown' AS description_zh,
    'Not specified' AS color,
    'Unknown' AS size,
    NULL AS production_cost;

DROP TABLE IF EXISTS stores_final;

CREATE TABLE stores_final AS
SELECT
    store_id,
    country,
    city,
    store_name,
    number_of_employees,
    zip_code,
    latitude,
    longitude
FROM stores

UNION ALL

SELECT
    'UNKNOWN_STORE' AS store_id,
    'Unknown' AS country,
    'Unknown' AS city,
    'Unknown Store' AS store_name,
    NULL AS number_of_employees,
    'Unknown' AS zip_code,
    NULL AS latitude,
    NULL AS longitude;

DROP TABLE IF EXISTS transactions_final;

CREATE TABLE transactions_final AS
WITH final_base AS (
    SELECT
        source_rowid,
        invoice_id,
        line_no,
        COALESCE(customer_id, 'UNKNOWN_CUSTOMER') AS customer_id,
        COALESCE(product_id, 'UNKNOWN_PRODUCT') AS product_id,
        COALESCE(size, 'Unknown') AS size,
        COALESCE(color, 'Not specified') AS color,
        COALESCE(unit_price, 0) AS unit_price,
        COALESCE(quantity, 0) AS quantity,
        transaction_datetime,
        transaction_date,
        COALESCE(discount, 0) AS discount,
        line_total,
        COALESCE(store_id, 'UNKNOWN_STORE') AS store_id,
        employee_id,
        currency,
        currency_symbol,
        COALESCE(sku, 'Not available') AS sku,
        transaction_type,
        COALESCE(payment_method, 'Unknown') AS payment_method,
        invoice_total,
        has_line_no,
        has_customer_id,
        has_product_id,
        has_unit_price,
        has_quantity
    FROM transactions_imputed
)
SELECT
    source_rowid,
    invoice_id,
    line_no,
    customer_id,
    product_id,
    size,
    color,
    unit_price,
    quantity,
    transaction_datetime,
    transaction_date,
    discount,
    COALESCE(line_total, 0) AS line_total,
    store_id,
    COALESCE(
        employee_id,
        'UNKNOWN_STORE_' || CASE
            WHEN store_id = 'UNKNOWN_STORE' THEN 'UNKNOWN'
            ELSE store_id
        END
    ) AS employee_id,
    currency,
    currency_symbol,
    sku,
    transaction_type,
    payment_method,
    COALESCE(invoice_total, 0) AS invoice_total,
    has_line_no,
    CASE WHEN customer_id <> 'UNKNOWN_CUSTOMER' THEN 1 ELSE 0 END AS has_customer_id,
    CASE WHEN product_id <> 'UNKNOWN_PRODUCT' THEN 1 ELSE 0 END AS has_product_id,
    CASE WHEN unit_price <> 0 THEN 1 ELSE 0 END AS has_unit_price,
    CASE WHEN quantity <> 0 THEN 1 ELSE 0 END AS has_quantity
FROM final_base;

DROP VIEW IF EXISTS v_invalid_foreign_keys;

CREATE VIEW v_invalid_foreign_keys AS
SELECT 'customer_id' AS field, t.customer_id AS invalid_value, COUNT(*) AS cnt
FROM transactions_final t
LEFT JOIN customers_final c
    ON t.customer_id = c.customer_id
WHERE t.customer_id IS NOT NULL
  AND c.customer_id IS NULL
GROUP BY t.customer_id

UNION ALL

SELECT 'product_id', t.product_id, COUNT(*)
FROM transactions_final t
LEFT JOIN products_final p
    ON t.product_id = p.product_id
WHERE t.product_id IS NOT NULL
  AND p.product_id IS NULL
GROUP BY t.product_id

UNION ALL

SELECT 'store_id', t.store_id, COUNT(*)
FROM transactions_final t
LEFT JOIN stores_final s
    ON t.store_id = s.store_id
WHERE t.store_id IS NOT NULL
  AND s.store_id IS NULL
GROUP BY t.store_id

UNION ALL

SELECT 'employee_id', t.employee_id, COUNT(*)
FROM transactions_final t
LEFT JOIN employees_final e
    ON t.employee_id = e.employee_id
WHERE t.employee_id IS NOT NULL
  AND e.employee_id IS NULL
GROUP BY t.employee_id;

DROP TABLE IF EXISTS transactions_clean;
DROP TABLE IF EXISTS transactions_rejected;
DROP TABLE IF EXISTS transactions_imputed;
DROP VIEW IF EXISTS v_transactions_clean;

DROP VIEW IF EXISTS v_cleaning_summary;

CREATE VIEW v_cleaning_summary AS
SELECT 'raw_rows' AS metric, COUNT(*) AS value FROM transactions
UNION ALL
SELECT 'final_rows', COUNT(*) FROM transactions_final
UNION ALL
SELECT 'invalid_foreign_key_rows', COALESCE(SUM(cnt), 0) FROM v_invalid_foreign_keys;

SELECT * FROM v_cleaning_summary;
