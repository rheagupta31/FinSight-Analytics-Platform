-- ============================================================
-- FINTECH PROJECT - PRACTICE QUERIES (Interview Style)
-- Run these one by one in DB Browser or via Python
-- ============================================================

-- ── Q1: Which customer has the highest expense-to-income ratio? ──
-- Tests: aggregation, HAVING, ratio calculation, ordering
SELECT
    c.full_name,
    ROUND(SUM(CASE WHEN t.txn_type = 'DEBIT'  THEN t.amount ELSE 0 END), 2) AS total_expenses,
    ROUND(SUM(CASE WHEN t.txn_type = 'CREDIT' THEN t.amount ELSE 0 END), 2) AS total_income,
    ROUND(
        SUM(CASE WHEN t.txn_type = 'DEBIT'  THEN t.amount ELSE 0 END) * 100.0 /
        NULLIF(SUM(CASE WHEN t.txn_type = 'CREDIT' THEN t.amount ELSE 0 END), 0),
    2)                                                              AS expense_ratio_pct,
    RANK() OVER (ORDER BY
        SUM(CASE WHEN t.txn_type = 'DEBIT'  THEN t.amount ELSE 0 END) * 1.0 /
        NULLIF(SUM(CASE WHEN t.txn_type = 'CREDIT' THEN t.amount ELSE 0 END), 0)
    DESC)                                                           AS rank_highest_spender
FROM customers c
JOIN accounts a    ON c.customer_id = a.customer_id
JOIN transactions t ON a.account_id = t.account_id
WHERE t.status = 'COMPLETED'
GROUP BY c.customer_id, c.full_name
ORDER BY expense_ratio_pct DESC;


-- ── Q2: Find all months where any customer spent more than they earned ──
-- Tests: GROUP BY with date functions, HAVING, subquery filtering
SELECT
    c.full_name,
    STRFTIME('%Y-%m', t.txn_date)                                  AS month,
    ROUND(SUM(CASE WHEN t.txn_type = 'CREDIT' THEN t.amount ELSE 0 END), 2) AS income,
    ROUND(SUM(CASE WHEN t.txn_type = 'DEBIT'  THEN t.amount ELSE 0 END), 2) AS expenses,
    ROUND(
        SUM(CASE WHEN t.txn_type = 'DEBIT'  THEN t.amount ELSE 0 END) -
        SUM(CASE WHEN t.txn_type = 'CREDIT' THEN t.amount ELSE 0 END),
    2)                                                              AS overspend_amount
FROM customers c
JOIN accounts a     ON c.customer_id = a.customer_id
JOIN transactions t ON a.account_id  = t.account_id
WHERE t.status = 'COMPLETED'
GROUP BY c.customer_id, c.full_name, STRFTIME('%Y-%m', t.txn_date)
HAVING expenses > income
ORDER BY overspend_amount DESC;


-- ── Q3: Rank customers by net worth (sum of all positive account balances) ──
-- Tests: conditional aggregation, window functions, RANK vs DENSE_RANK
SELECT
    c.full_name,
    PRINTF('$%,.2f', SUM(CASE WHEN a.balance > 0 THEN a.balance ELSE 0 END)) AS total_assets,
    PRINTF('$%,.2f', ABS(SUM(CASE WHEN a.balance < 0 THEN a.balance ELSE 0 END))) AS total_liabilities,
    PRINTF('$%,.2f',
        SUM(CASE WHEN a.balance > 0 THEN a.balance ELSE 0 END) +
        SUM(CASE WHEN a.balance < 0 THEN a.balance ELSE 0 END)
    )                                                               AS net_worth,
    RANK() OVER (ORDER BY
        SUM(CASE WHEN a.balance > 0 THEN a.balance ELSE 0 END) +
        SUM(CASE WHEN a.balance < 0 THEN a.balance ELSE 0 END)
    DESC)                                                           AS wealth_rank
FROM customers c
JOIN accounts a ON c.customer_id = a.customer_id
GROUP BY c.customer_id, c.full_name
ORDER BY wealth_rank;


-- ── Q4: What % of Bob's transactions were late or missed loan payments? ──
-- Tests: filtered aggregation, percentage calculation, specific customer lookup
SELECT
    c.full_name,
    COUNT(lp.payment_id)                                            AS total_loan_payments,
    SUM(CASE WHEN lp.status IN ('OVERDUE','PARTIAL') OR lp.days_late > 0
             THEN 1 ELSE 0 END)                                     AS problematic_payments,
    ROUND(
        SUM(CASE WHEN lp.status IN ('OVERDUE','PARTIAL') OR lp.days_late > 0
                 THEN 1 ELSE 0 END) * 100.0 / COUNT(lp.payment_id),
    1)                                                              AS pct_problematic,
    MAX(lp.days_late)                                               AS worst_late_days,
    SUM(lp.amount_due - lp.amount_paid)                             AS total_unpaid
FROM customers c
JOIN accounts a     ON c.customer_id = a.customer_id
JOIN loan_payments lp ON a.account_id = lp.account_id
WHERE c.full_name = 'Bob Martinez'
GROUP BY c.full_name;


-- ── Q5: Which spending category grew month-over-month? ──
-- Tests: LAG window function, CTEs, month-over-month growth
WITH monthly_spend AS (
    SELECT
        cat.category_name,
        STRFTIME('%Y-%m', t.txn_date)           AS month,
        ROUND(SUM(t.amount), 2)                 AS total_spent
    FROM transactions t
    JOIN categories cat ON t.category_id = cat.category_id
    WHERE t.txn_type = 'DEBIT'
      AND t.status   = 'COMPLETED'
      AND cat.category_type = 'EXPENSE'
    GROUP BY cat.category_name, STRFTIME('%Y-%m', t.txn_date)
),
with_growth AS (
    SELECT
        category_name,
        month,
        total_spent,
        LAG(total_spent) OVER (PARTITION BY category_name ORDER BY month) AS prev_month_spend,
        ROUND(
            (total_spent - LAG(total_spent) OVER (PARTITION BY category_name ORDER BY month)) * 100.0
            / NULLIF(LAG(total_spent) OVER (PARTITION BY category_name ORDER BY month), 0),
        1)                                       AS mom_growth_pct
    FROM monthly_spend
)
SELECT
    category_name,
    month,
    PRINTF('$%,.2f', total_spent)               AS spent,
    PRINTF('$%,.2f', COALESCE(prev_month_spend, 0)) AS prev_month,
    COALESCE(mom_growth_pct || '%', 'N/A (first month)') AS mom_growth
FROM with_growth
ORDER BY category_name, month;
