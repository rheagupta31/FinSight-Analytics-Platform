-- ============================================================
-- FINTECH PROJECT - LAYER 3: FRAUD DETECTION ENGINE
-- Rule-based fraud flagging system using SQL
-- ============================================================

-- ── FRAUD FLAGS TABLE ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS fraud_flags (
    flag_id         INTEGER PRIMARY KEY AUTOINCREMENT,
    transaction_id  INTEGER,
    account_id      INTEGER,
    customer_id     INTEGER,
    flag_type       TEXT    NOT NULL,
    severity        TEXT    NOT NULL CHECK(severity IN ('LOW','MEDIUM','HIGH','CRITICAL')),
    description     TEXT,
    flagged_at      DATETIME DEFAULT (DATETIME('now')),
    is_reviewed     INTEGER DEFAULT 0,
    is_confirmed_fraud INTEGER DEFAULT 0,
    FOREIGN KEY (transaction_id) REFERENCES transactions(transaction_id),
    FOREIGN KEY (account_id)     REFERENCES accounts(account_id),
    FOREIGN KEY (customer_id)    REFERENCES customers(customer_id)
);

-- ── RULE 1: Unusually Large Transactions ────────────────────
-- Flag any transaction > 3x the customer's average transaction size
-- Severity: HIGH

INSERT OR IGNORE INTO fraud_flags (transaction_id, account_id, customer_id, flag_type, severity, description)
SELECT
    t.transaction_id,
    t.account_id,
    a.customer_id,
    'LARGE_TRANSACTION',
    'HIGH',
    'Transaction of $' || t.amount || ' is more than 3x the account average of $' ||
    ROUND(avg_data.avg_amount, 2)
FROM transactions t
JOIN accounts a ON t.account_id = a.account_id
JOIN (
    SELECT
        account_id,
        AVG(amount)  AS avg_amount,
        STDEV_APPROX AS stdev_amount   -- We'll define this below
    FROM (
        SELECT
            account_id,
            amount,
            AVG(amount) OVER (PARTITION BY account_id) AS stdev_approx  -- reuse avg as proxy
        FROM transactions
        WHERE status = 'COMPLETED'
    )
    GROUP BY account_id
) avg_data ON t.account_id = avg_data.account_id
WHERE t.amount > avg_data.avg_amount * 3
  AND t.status = 'COMPLETED'
  AND t.txn_type = 'DEBIT';

-- ── RULE 1 (Corrected — SQLite-compatible) ───────────────────
DELETE FROM fraud_flags WHERE flag_type = 'LARGE_TRANSACTION';

INSERT OR IGNORE INTO fraud_flags (transaction_id, account_id, customer_id, flag_type, severity, description)
SELECT
    t.transaction_id,
    t.account_id,
    a.customer_id,
    'LARGE_TRANSACTION',
    'HIGH',
    'Debit of $' || t.amount || ' exceeds 3x account avg ($' || ROUND(avg_data.avg_amount, 2) || ')'
FROM transactions t
JOIN accounts a ON t.account_id = a.account_id
JOIN (
    SELECT account_id, AVG(amount) AS avg_amount
    FROM transactions
    WHERE status = 'COMPLETED' AND txn_type = 'DEBIT'
    GROUP BY account_id
) avg_data ON t.account_id = avg_data.account_id
WHERE t.txn_type = 'DEBIT'
  AND t.status   = 'COMPLETED'
  AND t.amount   > avg_data.avg_amount * 3;


-- ── RULE 2: Rapid Successive Transactions ───────────────────
-- 3+ transactions within 10 minutes = velocity fraud
-- Severity: CRITICAL

INSERT OR IGNORE INTO fraud_flags (transaction_id, account_id, customer_id, flag_type, severity, description)
SELECT DISTINCT
    t.transaction_id,
    t.account_id,
    a.customer_id,
    'VELOCITY_FRAUD',
    'CRITICAL',
    'Multiple rapid transactions detected within 10 minutes'
FROM transactions t
JOIN accounts a ON t.account_id = a.account_id
WHERE (
    SELECT COUNT(*)
    FROM transactions t2
    WHERE t2.account_id = t.account_id
      AND t2.status = 'COMPLETED'
      AND ABS(JULIANDAY(t2.txn_date) - JULIANDAY(t.txn_date)) * 24 * 60 <= 10
      AND t2.transaction_id != t.transaction_id
) >= 2;


-- ── RULE 3: International Transaction Anomaly ───────────────
-- Transaction from a foreign country when account has no history there
-- Severity: MEDIUM

INSERT OR IGNORE INTO fraud_flags (transaction_id, account_id, customer_id, flag_type, severity, description)
SELECT
    t.transaction_id,
    t.account_id,
    a.customer_id,
    'FOREIGN_TRANSACTION',
    'MEDIUM',
    'Transaction from unusual country: ' || t.merchant_country
FROM transactions t
JOIN accounts a ON t.account_id = a.account_id
WHERE t.merchant_country != 'US'
  AND t.status = 'COMPLETED'
  AND NOT EXISTS (
      SELECT 1 FROM transactions t_hist
      WHERE t_hist.account_id      = t.account_id
        AND t_hist.merchant_country = t.merchant_country
        AND t_hist.txn_date         < t.txn_date
        AND t_hist.status          = 'COMPLETED'
  );


-- ── RULE 4: Spending > Income (Account Drain) ───────────────
-- Monthly outflows exceed inflows — possible account takeover
-- Severity: HIGH

INSERT OR IGNORE INTO fraud_flags (transaction_id, account_id, customer_id, flag_type, severity, description)
SELECT
    NULL,
    monthly.account_id,
    a.customer_id,
    'SPENDING_EXCEEDS_INCOME',
    'HIGH',
    'Month ' || monthly.txn_month || ': Debits ($' || ROUND(monthly.total_debits,2) ||
    ') exceeded credits ($' || ROUND(monthly.total_credits,2) || ') by ' ||
    ROUND(((monthly.total_debits - monthly.total_credits) / monthly.total_credits) * 100, 1) || '%'
FROM (
    SELECT
        account_id,
        STRFTIME('%Y-%m', txn_date)                                                    AS txn_month,
        SUM(CASE WHEN txn_type = 'DEBIT'  AND status = 'COMPLETED' THEN amount ELSE 0 END) AS total_debits,
        SUM(CASE WHEN txn_type = 'CREDIT' AND status = 'COMPLETED' THEN amount ELSE 0 END) AS total_credits
    FROM transactions
    GROUP BY account_id, STRFTIME('%Y-%m', txn_date)
    HAVING total_credits > 0
       AND total_debits > total_credits * 1.5   -- spending 50% more than income
) monthly
JOIN accounts a ON monthly.account_id = a.account_id;


-- ── RULE 5: Dormant Account Sudden Activity ─────────────────
-- No activity for 60+ days, then sudden transactions
-- Severity: MEDIUM

INSERT OR IGNORE INTO fraud_flags (transaction_id, account_id, customer_id, flag_type, severity, description)
SELECT
    t.transaction_id,
    t.account_id,
    a.customer_id,
    'DORMANT_ACCOUNT_ACTIVITY',
    'MEDIUM',
    'Transaction after ' || CAST(ROUND(JULIANDAY(t.txn_date) - JULIANDAY(last_txn.last_date)) AS INTEGER) || ' days of inactivity'
FROM transactions t
JOIN accounts a ON t.account_id = a.account_id
JOIN (
    SELECT
        t1.transaction_id,
        t1.account_id,
        MAX(t2.txn_date) AS last_date
    FROM transactions t1
    JOIN transactions t2
      ON t2.account_id = t1.account_id
     AND t2.txn_date   < t1.txn_date
     AND t2.status     = 'COMPLETED'
    GROUP BY t1.transaction_id, t1.account_id
    HAVING (JULIANDAY(t1.txn_date) - JULIANDAY(MAX(t2.txn_date))) > 60
) last_txn ON t.transaction_id = last_txn.transaction_id
WHERE t.status = 'COMPLETED';


-- ── FRAUD SUMMARY VIEW ───────────────────────────────────────
CREATE VIEW IF NOT EXISTS v_fraud_summary AS
SELECT
    c.customer_id,
    c.full_name,
    COUNT(ff.flag_id)                                                       AS total_flags,
    SUM(CASE WHEN ff.severity = 'CRITICAL' THEN 1 ELSE 0 END)              AS critical_flags,
    SUM(CASE WHEN ff.severity = 'HIGH'     THEN 1 ELSE 0 END)              AS high_flags,
    SUM(CASE WHEN ff.severity = 'MEDIUM'   THEN 1 ELSE 0 END)              AS medium_flags,
    SUM(CASE WHEN ff.severity = 'LOW'      THEN 1 ELSE 0 END)              AS low_flags,
    GROUP_CONCAT(DISTINCT ff.flag_type)                                     AS flag_types,
    -- Risk level
    CASE
        WHEN SUM(CASE WHEN ff.severity = 'CRITICAL' THEN 1 ELSE 0 END) > 0  THEN 'CRITICAL RISK'
        WHEN SUM(CASE WHEN ff.severity = 'HIGH'     THEN 1 ELSE 0 END) >= 2  THEN 'HIGH RISK'
        WHEN SUM(CASE WHEN ff.severity = 'HIGH'     THEN 1 ELSE 0 END) = 1   THEN 'MEDIUM RISK'
        WHEN COUNT(ff.flag_id) > 0                                           THEN 'LOW RISK'
        ELSE 'CLEAN'
    END                                                                     AS risk_level
FROM customers c
LEFT JOIN fraud_flags ff ON c.customer_id = ff.customer_id
GROUP BY c.customer_id, c.full_name;


-- ── COMBINED DASHBOARD VIEW ──────────────────────────────────
-- Joins credit scores + fraud risk for a full customer risk profile
CREATE VIEW IF NOT EXISTS v_customer_risk_dashboard AS
SELECT
    cs.customer_id,
    cs.full_name,
    cs.credit_score,
    cs.credit_grade,
    cs.composite_score,
    COALESCE(fs.risk_level,   'CLEAN')  AS fraud_risk_level,
    COALESCE(fs.total_flags,  0)        AS fraud_flags,
    COALESCE(fs.critical_flags,0)       AS critical_fraud_flags,
    COALESCE(fs.flag_types,  'None')    AS fraud_flag_types,
    -- Overall risk decision
    CASE
        WHEN fs.risk_level = 'CRITICAL RISK'                       THEN 'DECLINE — FREEZE ACCOUNT'
        WHEN fs.risk_level = 'HIGH RISK' AND cs.credit_score < 580 THEN 'DECLINE — HIGH RISK'
        WHEN fs.risk_level = 'HIGH RISK'                           THEN 'MANUAL REVIEW REQUIRED'
        WHEN cs.credit_score < 580                                 THEN 'DECLINE — POOR CREDIT'
        WHEN cs.credit_score < 670                                 THEN 'CONDITIONAL APPROVAL'
        ELSE                                                             'APPROVED'
    END                                                             AS loan_decision
FROM v_credit_scores cs
LEFT JOIN v_fraud_summary fs ON cs.customer_id = fs.customer_id;
