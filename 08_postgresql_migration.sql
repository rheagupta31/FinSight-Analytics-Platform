-- ============================================================
-- FINTECH PROJECT - PostgreSQL Migration Guide
-- How to move from SQLite → PostgreSQL (production-ready)
-- ============================================================
-- Step 1: Install PostgreSQL on your machine
--   Mac:   brew install postgresql && brew services start postgresql
--   Linux: sudo apt install postgresql
--
-- Step 2: Create a database
--   psql -U postgres -c "CREATE DATABASE fintech_db;"
--
-- Step 3: Run this file in psql
--   psql -U postgres -d fintech_db -f 08_postgresql_migration.sql
-- ============================================================

-- ── Key differences from SQLite ─────────────────────────────
-- 1. AUTOINCREMENT → SERIAL or GENERATED ALWAYS AS IDENTITY
-- 2. INTEGER DEFAULT 1 → BOOLEAN DEFAULT TRUE
-- 3. DATETIME → TIMESTAMP
-- 4. STRFTIME() → TO_CHAR() / DATE_TRUNC()
-- 5. JULIANDAY() → EXTRACT(EPOCH FROM ...) or AGE()
-- 6. POWER() → same in PostgreSQL ✓

-- ── CUSTOMERS ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS customers (
    customer_id     SERIAL PRIMARY KEY,
    full_name       VARCHAR(100)  NOT NULL,
    email           VARCHAR(150)  UNIQUE NOT NULL,
    phone           VARCHAR(20),
    date_of_birth   DATE,
    joined_date     DATE          DEFAULT CURRENT_DATE,
    credit_limit    NUMERIC(12,2) DEFAULT 5000.00,
    is_active       BOOLEAN       DEFAULT TRUE
);

-- ── ACCOUNTS ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS accounts (
    account_id      SERIAL PRIMARY KEY,
    customer_id     INTEGER       NOT NULL REFERENCES customers(customer_id),
    account_type    VARCHAR(10)   NOT NULL CHECK (account_type IN ('CHECKING','SAVINGS','CREDIT','LOAN')),
    account_number  VARCHAR(30)   UNIQUE NOT NULL,
    balance         NUMERIC(15,2) DEFAULT 0.00,
    currency        CHAR(3)       DEFAULT 'USD',
    opened_date     DATE          DEFAULT CURRENT_DATE,
    is_active       BOOLEAN       DEFAULT TRUE
);

-- ── CATEGORIES ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS categories (
    category_id     SERIAL PRIMARY KEY,
    category_name   VARCHAR(50)   UNIQUE NOT NULL,
    category_type   VARCHAR(10)   NOT NULL CHECK (category_type IN ('INCOME','EXPENSE','TRANSFER'))
);

-- ── TRANSACTIONS ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS transactions (
    transaction_id  SERIAL PRIMARY KEY,
    account_id      INTEGER       NOT NULL REFERENCES accounts(account_id),
    category_id     INTEGER       REFERENCES categories(category_id),
    txn_date        TIMESTAMP     DEFAULT NOW(),
    amount          NUMERIC(12,2) NOT NULL,
    txn_type        VARCHAR(6)    NOT NULL CHECK (txn_type IN ('DEBIT','CREDIT')),
    description     TEXT,
    reference_id    VARCHAR(50),
    merchant_name   VARCHAR(100),
    merchant_city   VARCHAR(100),
    merchant_country CHAR(2)      DEFAULT 'US',
    channel         VARCHAR(20)   CHECK (channel IN ('ATM','ONLINE','POS','TRANSFER','DIRECT_DEPOSIT')),
    status          VARCHAR(10)   DEFAULT 'COMPLETED'
                                  CHECK (status IN ('COMPLETED','PENDING','FAILED','REVERSED'))
);

-- ── LOAN PAYMENTS ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS loan_payments (
    payment_id      SERIAL PRIMARY KEY,
    account_id      INTEGER       NOT NULL REFERENCES accounts(account_id),
    due_date        DATE          NOT NULL,
    amount_due      NUMERIC(10,2) NOT NULL,
    principal       NUMERIC(10,2) NOT NULL,
    interest        NUMERIC(10,2) NOT NULL,
    amount_paid     NUMERIC(10,2) DEFAULT 0.00,
    paid_date       DATE,
    status          VARCHAR(10)   DEFAULT 'PENDING'
                                  CHECK (status IN ('PENDING','PAID','OVERDUE','PARTIAL')),
    days_late       INTEGER       DEFAULT 0
);

-- ── INDEXES ──────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_txn_account  ON transactions(account_id);
CREATE INDEX IF NOT EXISTS idx_txn_date     ON transactions(txn_date);
CREATE INDEX IF NOT EXISTS idx_txn_status   ON transactions(status);
CREATE INDEX IF NOT EXISTS idx_acc_customer ON accounts(customer_id);

-- ── PostgreSQL-equivalent of SQLite date functions ───────────
-- SQLite                          → PostgreSQL
-- STRFTIME('%Y-%m', txn_date)     → TO_CHAR(txn_date, 'YYYY-MM')
-- DATE('now', '-90 days')         → NOW() - INTERVAL '90 days'
-- JULIANDAY(d2) - JULIANDAY(d1)   → EXTRACT(DAY FROM (d2::timestamp - d1::timestamp))
-- DATE('now')                     → CURRENT_DATE

-- ── Example PostgreSQL-style monthly trend query ─────────────
-- SELECT
--     TO_CHAR(txn_date, 'YYYY-MM')                     AS month,
--     SUM(CASE WHEN txn_type = 'CREDIT' THEN amount ELSE 0 END) AS income,
--     SUM(CASE WHEN txn_type = 'DEBIT'  THEN amount ELSE 0 END) AS expenses
-- FROM transactions
-- WHERE status = 'COMPLETED'
-- GROUP BY TO_CHAR(txn_date, 'YYYY-MM')
-- ORDER BY month;

-- ── Migrate data from SQLite using Python ────────────────────
-- See the comment block below for the Python migration script idea:
--
-- import sqlite3, psycopg2, pandas as pd
-- sqlite_conn = sqlite3.connect('fintech.db')
-- pg_conn     = psycopg2.connect("dbname=fintech_db user=postgres")
-- for table in ['customers','accounts','categories','transactions','loan_payments']:
--     df = pd.read_sql(f'SELECT * FROM {table}', sqlite_conn)
--     df.to_sql(table, pg_conn, if_exists='append', index=False)
-- print("Migration complete!")
