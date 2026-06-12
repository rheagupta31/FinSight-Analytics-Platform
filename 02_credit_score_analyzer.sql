-- ============================================================
-- FINTECH PROJECT - LAYER 2: CREDIT SCORE ANALYZER
-- Computes a simplified credit score (300–850) using 5 factors
-- modeled after real FICO methodology
-- ============================================================

-- ── FACTOR 1: Payment History (35% weight) ──────────────────
-- Checks loan_payments for late/missed payments
-- Score: 100 pts if perfect, deducted for late/missed payments

CREATE VIEW IF NOT EXISTS v_payment_history AS
SELECT
    a.customer_id,
    COUNT(lp.payment_id)                                        AS total_payments,
    SUM(CASE WHEN lp.status = 'PAID'    THEN 1 ELSE 0 END)     AS on_time_payments,
    SUM(CASE WHEN lp.status = 'OVERDUE' THEN 1 ELSE 0 END)     AS missed_payments,
    SUM(CASE WHEN lp.status = 'PARTIAL' THEN 1 ELSE 0 END)     AS partial_payments,
    SUM(CASE WHEN lp.days_late > 0 THEN 1 ELSE 0 END)          AS late_payments,
    MAX(lp.days_late)                                           AS max_days_late,
    -- Payment score: start at 100, deduct for issues
    MAX(0,
        100
        - (SUM(CASE WHEN lp.status = 'OVERDUE' THEN 1 ELSE 0 END) * 25)
        - (SUM(CASE WHEN lp.status = 'PARTIAL' THEN 1 ELSE 0 END) * 10)
        - (SUM(CASE WHEN lp.days_late BETWEEN 1  AND 29  THEN 1 ELSE 0 END) * 5)
        - (SUM(CASE WHEN lp.days_late BETWEEN 30 AND 59  THEN 1 ELSE 0 END) * 15)
        - (SUM(CASE WHEN lp.days_late >= 60               THEN 1 ELSE 0 END) * 30)
    )                                                           AS payment_score
FROM accounts a
LEFT JOIN loan_payments lp ON a.account_id = lp.account_id
GROUP BY a.customer_id;


-- ── FACTOR 2: Credit Utilization (30% weight) ───────────────
-- Ratio of credit card balance to credit limit
-- Lower is better. >30% hurts score, >70% hurts badly

CREATE VIEW IF NOT EXISTS v_credit_utilization AS
SELECT
    a.customer_id,
    SUM(CASE WHEN a.account_type = 'CREDIT' THEN ABS(a.balance) ELSE 0 END) AS total_credit_used,
    SUM(CASE WHEN a.account_type = 'CREDIT' THEN c.credit_limit ELSE 0 END) AS total_credit_limit,
    ROUND(
        CASE
            WHEN SUM(CASE WHEN a.account_type = 'CREDIT' THEN c.credit_limit ELSE 0 END) = 0
            THEN 0
            ELSE (SUM(CASE WHEN a.account_type = 'CREDIT' THEN ABS(a.balance) ELSE 0 END) * 100.0)
                 / SUM(CASE WHEN a.account_type = 'CREDIT' THEN c.credit_limit ELSE 0 END)
        END, 2
    )                                                           AS utilization_pct,
    -- Utilization score
    CASE
        WHEN SUM(CASE WHEN a.account_type = 'CREDIT' THEN c.credit_limit ELSE 0 END) = 0
             THEN 80  -- no credit card = neutral
        WHEN (SUM(CASE WHEN a.account_type = 'CREDIT' THEN ABS(a.balance) ELSE 0 END) * 100.0)
              / SUM(CASE WHEN a.account_type = 'CREDIT' THEN c.credit_limit ELSE 0 END) <= 10
             THEN 100
        WHEN (SUM(CASE WHEN a.account_type = 'CREDIT' THEN ABS(a.balance) ELSE 0 END) * 100.0)
              / SUM(CASE WHEN a.account_type = 'CREDIT' THEN c.credit_limit ELSE 0 END) <= 30
             THEN 85
        WHEN (SUM(CASE WHEN a.account_type = 'CREDIT' THEN ABS(a.balance) ELSE 0 END) * 100.0)
              / SUM(CASE WHEN a.account_type = 'CREDIT' THEN c.credit_limit ELSE 0 END) <= 50
             THEN 65
        WHEN (SUM(CASE WHEN a.account_type = 'CREDIT' THEN ABS(a.balance) ELSE 0 END) * 100.0)
              / SUM(CASE WHEN a.account_type = 'CREDIT' THEN c.credit_limit ELSE 0 END) <= 70
             THEN 45
        ELSE 20
    END                                                         AS utilization_score
FROM accounts a
JOIN customers c ON a.customer_id = c.customer_id
GROUP BY a.customer_id;


-- ── FACTOR 3: Account Age / Credit History Length (15%) ─────
-- Older accounts = more trustworthy

CREATE VIEW IF NOT EXISTS v_account_age AS
SELECT
    customer_id,
    MIN(opened_date)                                            AS oldest_account,
    MAX(opened_date)                                            AS newest_account,
    ROUND((JULIANDAY('now') - JULIANDAY(MIN(opened_date))) / 365.25, 1) AS years_oldest,
    COUNT(account_id)                                           AS total_accounts,
    -- Age score
    CASE
        WHEN (JULIANDAY('now') - JULIANDAY(MIN(opened_date))) / 365.25 >= 7  THEN 100
        WHEN (JULIANDAY('now') - JULIANDAY(MIN(opened_date))) / 365.25 >= 5  THEN 85
        WHEN (JULIANDAY('now') - JULIANDAY(MIN(opened_date))) / 365.25 >= 3  THEN 70
        WHEN (JULIANDAY('now') - JULIANDAY(MIN(opened_date))) / 365.25 >= 1  THEN 50
        ELSE 25
    END                                                         AS age_score
FROM accounts
GROUP BY customer_id;


-- ── FACTOR 4: Credit Mix (10% weight) ───────────────────────
-- Having different types of accounts (checking, savings, credit, loan) is good

CREATE VIEW IF NOT EXISTS v_credit_mix AS
SELECT
    customer_id,
    COUNT(DISTINCT account_type)                                AS account_types_count,
    GROUP_CONCAT(DISTINCT account_type)                         AS account_types,
    -- Mix score
    CASE
        WHEN COUNT(DISTINCT account_type) >= 4 THEN 100
        WHEN COUNT(DISTINCT account_type) = 3  THEN 80
        WHEN COUNT(DISTINCT account_type) = 2  THEN 60
        ELSE 40
    END                                                         AS mix_score
FROM accounts
GROUP BY customer_id;


-- ── FACTOR 5: Recent Activity / New Inquiries (10% weight) ──
-- High spending or many new transactions recently can signal risk

CREATE VIEW IF NOT EXISTS v_recent_activity AS
SELECT
    a.customer_id,
    COUNT(t.transaction_id)                                     AS txns_last_90_days,
    COALESCE(SUM(CASE WHEN t.txn_type = 'DEBIT' THEN t.amount ELSE 0 END), 0) AS total_debits_90d,
    COALESCE(SUM(CASE WHEN t.txn_type = 'CREDIT' THEN t.amount ELSE 0 END), 0) AS total_credits_90d,
    -- Activity score: penalize if spending >> income
    CASE
        WHEN COUNT(t.transaction_id) = 0 THEN 50
        WHEN COALESCE(SUM(CASE WHEN t.txn_type = 'CREDIT' THEN t.amount ELSE 0 END), 0) = 0 THEN 40
        WHEN (COALESCE(SUM(CASE WHEN t.txn_type = 'DEBIT' THEN t.amount ELSE 0 END), 0) /
              COALESCE(SUM(CASE WHEN t.txn_type = 'CREDIT' THEN t.amount ELSE 0 END), 1)) <= 0.6 THEN 100
        WHEN (COALESCE(SUM(CASE WHEN t.txn_type = 'DEBIT' THEN t.amount ELSE 0 END), 0) /
              COALESCE(SUM(CASE WHEN t.txn_type = 'CREDIT' THEN t.amount ELSE 0 END), 1)) <= 0.8 THEN 85
        WHEN (COALESCE(SUM(CASE WHEN t.txn_type = 'DEBIT' THEN t.amount ELSE 0 END), 0) /
              COALESCE(SUM(CASE WHEN t.txn_type = 'CREDIT' THEN t.amount ELSE 0 END), 1)) <= 1.0 THEN 65
        ELSE 40
    END                                                         AS activity_score
FROM accounts a
LEFT JOIN transactions t
       ON a.account_id = t.account_id
      AND t.txn_date >= DATE('now', '-90 days')
      AND t.status = 'COMPLETED'
GROUP BY a.customer_id;


-- ── FINAL CREDIT SCORE VIEW ──────────────────────────────────
-- Combines all 5 factors with FICO-like weights
-- Maps weighted score (0-100) → credit score range (300-850)

CREATE VIEW IF NOT EXISTS v_credit_scores AS
SELECT
    c.customer_id,
    c.full_name,
    c.email,

    -- Individual factor scores
    COALESCE(ph.payment_score,    80) AS payment_score,       -- 35% weight
    COALESCE(cu.utilization_score,80) AS utilization_score,   -- 30% weight
    COALESCE(aa.age_score,        50) AS age_score,           -- 15% weight
    COALESCE(cm.mix_score,        60) AS mix_score,           -- 10% weight
    COALESCE(ra.activity_score,   60) AS activity_score,      -- 10% weight

    -- Weighted composite score (0-100)
    ROUND(
        COALESCE(ph.payment_score,    80) * 0.35 +
        COALESCE(cu.utilization_score,80) * 0.30 +
        COALESCE(aa.age_score,        50) * 0.15 +
        COALESCE(cm.mix_score,        60) * 0.10 +
        COALESCE(ra.activity_score,   60) * 0.10,
    2)                                                         AS composite_score,

    -- Map 0-100 → 300-850 credit score
    CAST(300 + ROUND(
        (
            COALESCE(ph.payment_score,    80) * 0.35 +
            COALESCE(cu.utilization_score,80) * 0.30 +
            COALESCE(aa.age_score,        50) * 0.15 +
            COALESCE(cm.mix_score,        60) * 0.10 +
            COALESCE(ra.activity_score,   60) * 0.10
        ) * 5.50   -- scale factor: 100 * 5.5 + 300 = 850
    ) AS INTEGER)                                              AS credit_score,

    -- Grade
    CASE
        WHEN CAST(300 + ROUND((
            COALESCE(ph.payment_score,    80) * 0.35 +
            COALESCE(cu.utilization_score,80) * 0.30 +
            COALESCE(aa.age_score,        50) * 0.15 +
            COALESCE(cm.mix_score,        60) * 0.10 +
            COALESCE(ra.activity_score,   60) * 0.10
        ) * 5.50) AS INTEGER) >= 750 THEN 'EXCELLENT'
        WHEN CAST(300 + ROUND((
            COALESCE(ph.payment_score,    80) * 0.35 +
            COALESCE(cu.utilization_score,80) * 0.30 +
            COALESCE(aa.age_score,        50) * 0.15 +
            COALESCE(cm.mix_score,        60) * 0.10 +
            COALESCE(ra.activity_score,   60) * 0.10
        ) * 5.50) AS INTEGER) >= 670 THEN 'GOOD'
        WHEN CAST(300 + ROUND((
            COALESCE(ph.payment_score,    80) * 0.35 +
            COALESCE(cu.utilization_score,80) * 0.30 +
            COALESCE(aa.age_score,        50) * 0.15 +
            COALESCE(cm.mix_score,        60) * 0.10 +
            COALESCE(ra.activity_score,   60) * 0.10
        ) * 5.50) AS INTEGER) >= 580 THEN 'FAIR'
        ELSE 'POOR'
    END                                                        AS credit_grade

FROM customers c
LEFT JOIN v_payment_history  ph ON c.customer_id = ph.customer_id
LEFT JOIN v_credit_utilization cu ON c.customer_id = cu.customer_id
LEFT JOIN v_account_age       aa ON c.customer_id = aa.customer_id
LEFT JOIN v_credit_mix        cm ON c.customer_id = cm.customer_id
LEFT JOIN v_recent_activity   ra ON c.customer_id = ra.customer_id;
