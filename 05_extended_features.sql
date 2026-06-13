-- ============================================================
-- FINTECH PROJECT - LAYER 4: EXTENDED FEATURES
-- Monthly trends, interest calculator, customer segmentation
-- ============================================================

-- ── FEATURE 1: Monthly Trend Report ─────────────────────────
CREATE VIEW IF NOT EXISTS v_monthly_trends AS
WITH monthly AS (
    SELECT
        a.customer_id,
        STRFTIME('%Y-%m', t.txn_date)                                   AS month,
        SUM(CASE WHEN t.txn_type = 'CREDIT' AND t.status='COMPLETED'
                 THEN t.amount ELSE 0 END)                               AS income,
        SUM(CASE WHEN t.txn_type = 'DEBIT'  AND t.status='COMPLETED'
                 THEN t.amount ELSE 0 END)                               AS expenses,
        COUNT(CASE WHEN t.status='COMPLETED' THEN 1 END)                 AS txn_count
    FROM accounts a
    JOIN transactions t ON a.account_id = t.account_id
    GROUP BY a.customer_id, STRFTIME('%Y-%m', t.txn_date)
)
SELECT
    c.full_name,
    m.month,
    ROUND(m.income,    2)                                               AS income,
    ROUND(m.expenses,  2)                                               AS expenses,
    ROUND(m.income - m.expenses, 2)                                     AS net_savings,
    m.txn_count,
    -- Month-over-month savings change
    ROUND(
        (m.income - m.expenses) -
        LAG(m.income - m.expenses) OVER (PARTITION BY m.customer_id ORDER BY m.month),
    2)                                                                  AS savings_mom_change,
    -- Savings rate %
    ROUND(CASE WHEN m.income > 0
          THEN ((m.income - m.expenses) / m.income) * 100
          ELSE 0 END, 1)                                                AS savings_rate_pct
FROM monthly m
JOIN customers c ON m.customer_id = c.customer_id
ORDER BY c.full_name, m.month;


-- ── FEATURE 2: Compound Interest Calculator ─────────────────
-- Generates a 12-month projection for each savings account
-- Formula: A = P(1 + r/n)^(nt)
CREATE VIEW IF NOT EXISTS v_savings_projections AS
WITH RECURSIVE months(n) AS (
    SELECT 1
    UNION ALL
    SELECT n + 1 FROM months WHERE n < 12
)
SELECT
    c.full_name,
    a.account_number,
    a.balance                                                           AS principal,
    3.5                                                                 AS annual_rate_pct,
    m.n                                                                 AS month_number,
    ROUND(a.balance * POWER(1 + (3.5/100/12), m.n), 2)                 AS projected_balance,
    ROUND(a.balance * POWER(1 + (3.5/100/12), m.n) - a.balance, 2)     AS interest_earned
FROM accounts a
JOIN customers c ON a.customer_id = c.customer_id
CROSS JOIN months m
WHERE a.account_type = 'SAVINGS'
  AND a.balance > 0
  AND a.is_active = 1
ORDER BY c.full_name, m.n;


-- ── FEATURE 3: Customer Segmentation ────────────────────────
-- Segments customers into: High Value / Growing / Stable / At Risk / Churned
CREATE VIEW IF NOT EXISTS v_customer_segments AS
WITH customer_stats AS (
    SELECT
        c.customer_id,
        c.full_name,
        -- Total net worth
        SUM(CASE WHEN a.balance > 0 THEN a.balance ELSE 0 END)         AS total_assets,
        -- Average monthly income
        AVG(monthly_income.monthly_amt)                                 AS avg_monthly_income,
        -- Transaction recency (days since last txn)
        CAST(JULIANDAY('now') - JULIANDAY(MAX(t.txn_date)) AS INTEGER)  AS days_since_last_txn,
        -- Total transaction count
        COUNT(t.transaction_id)                                         AS total_txns,
        -- Savings rate
        ROUND(
            (SUM(CASE WHEN t.txn_type='CREDIT' THEN t.amount ELSE 0 END) -
             SUM(CASE WHEN t.txn_type='DEBIT'  THEN t.amount ELSE 0 END)) * 100.0 /
            NULLIF(SUM(CASE WHEN t.txn_type='CREDIT' THEN t.amount ELSE 0 END), 0),
        1)                                                              AS savings_rate_pct
    FROM customers c
    JOIN accounts a ON c.customer_id = a.customer_id
    LEFT JOIN transactions t ON a.account_id = t.account_id AND t.status = 'COMPLETED'
    LEFT JOIN (
        SELECT a2.customer_id,
               STRFTIME('%Y-%m', t2.txn_date)   AS month,
               SUM(t2.amount)                   AS monthly_amt
        FROM transactions t2
        JOIN accounts a2 ON t2.account_id = a2.account_id
        WHERE t2.txn_type = 'CREDIT' AND t2.status = 'COMPLETED'
        GROUP BY a2.customer_id, STRFTIME('%Y-%m', t2.txn_date)
    ) monthly_income ON c.customer_id = monthly_income.customer_id
    GROUP BY c.customer_id, c.full_name
)
SELECT
    customer_id,
    full_name,
    ROUND(total_assets, 2)                                              AS total_assets,
    ROUND(COALESCE(avg_monthly_income, 0), 2)                          AS avg_monthly_income,
    days_since_last_txn,
    total_txns,
    COALESCE(savings_rate_pct, 0)                                      AS savings_rate_pct,
    -- Segment logic
    CASE
        WHEN days_since_last_txn > 90                                   THEN 'CHURNED'
        WHEN total_assets > 50000 AND savings_rate_pct > 50             THEN 'HIGH VALUE'
        WHEN savings_rate_pct > 60                                      THEN 'GROWING'
        WHEN savings_rate_pct BETWEEN 20 AND 60                         THEN 'STABLE'
        WHEN savings_rate_pct < 20 OR total_assets < 1000               THEN 'AT RISK'
        ELSE 'STABLE'
    END                                                                 AS segment,
    -- Recommended action
    CASE
        WHEN days_since_last_txn > 90   THEN 'Send re-engagement offer'
        WHEN total_assets > 50000 AND savings_rate_pct > 50
                                        THEN 'Offer premium investment products'
        WHEN savings_rate_pct > 60      THEN 'Offer high-yield savings account'
        WHEN savings_rate_pct < 20      THEN 'Send budgeting tips + financial advisor'
        ELSE 'Standard engagement'
    END                                                                 AS recommended_action
FROM customer_stats
ORDER BY total_assets DESC;
