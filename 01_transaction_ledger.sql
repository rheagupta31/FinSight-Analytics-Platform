-- ============================================================
-- FINTECH PROJECT - LAYER 1: TRANSACTION LEDGER
-- Double-entry bookkeeping system
-- ============================================================

-- ── CUSTOMERS ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS customers (
    customer_id     INTEGER PRIMARY KEY AUTOINCREMENT,
    full_name       TEXT    NOT NULL,
    email           TEXT    UNIQUE NOT NULL,
    phone           TEXT,
    date_of_birth   DATE,
    joined_date     DATE    DEFAULT (DATE('now')),
    credit_limit    REAL    DEFAULT 5000.00,
    is_active       INTEGER DEFAULT 1   -- 1=active, 0=inactive
);

-- ── ACCOUNTS ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS accounts (
    account_id      INTEGER PRIMARY KEY AUTOINCREMENT,
    customer_id     INTEGER NOT NULL,
    account_type    TEXT    NOT NULL CHECK(account_type IN ('CHECKING','SAVINGS','CREDIT','LOAN')),
    account_number  TEXT    UNIQUE NOT NULL,
    balance         REAL    DEFAULT 0.00,
    currency        TEXT    DEFAULT 'USD',
    opened_date     DATE    DEFAULT (DATE('now')),
    is_active       INTEGER DEFAULT 1,
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);

-- ── TRANSACTION CATEGORIES ──────────────────────────────────
CREATE TABLE IF NOT EXISTS categories (
    category_id     INTEGER PRIMARY KEY AUTOINCREMENT,
    category_name   TEXT    UNIQUE NOT NULL,
    category_type   TEXT    NOT NULL CHECK(category_type IN ('INCOME','EXPENSE','TRANSFER'))
);

-- ── TRANSACTIONS (Double-Entry Ledger) ──────────────────────
-- Every financial event creates TWO entries: a debit and a credit
CREATE TABLE IF NOT EXISTS transactions (
    transaction_id  INTEGER PRIMARY KEY AUTOINCREMENT,
    account_id      INTEGER NOT NULL,
    category_id     INTEGER,
    txn_date        DATETIME DEFAULT (DATETIME('now')),
    amount          REAL    NOT NULL,               -- always positive
    txn_type        TEXT    NOT NULL CHECK(txn_type IN ('DEBIT','CREDIT')),
    description     TEXT,
    reference_id    TEXT,                           -- links debit & credit pair
    merchant_name   TEXT,
    merchant_city   TEXT,
    merchant_country TEXT   DEFAULT 'US',
    channel         TEXT    CHECK(channel IN ('ATM','ONLINE','POS','TRANSFER','DIRECT_DEPOSIT')),
    status          TEXT    DEFAULT 'COMPLETED' CHECK(status IN ('COMPLETED','PENDING','FAILED','REVERSED')),
    FOREIGN KEY (account_id)  REFERENCES accounts(account_id),
    FOREIGN KEY (category_id) REFERENCES categories(category_id)
);

-- ── LOAN SCHEDULES ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS loan_payments (
    payment_id      INTEGER PRIMARY KEY AUTOINCREMENT,
    account_id      INTEGER NOT NULL,
    due_date        DATE    NOT NULL,
    amount_due      REAL    NOT NULL,
    principal       REAL    NOT NULL,
    interest        REAL    NOT NULL,
    amount_paid     REAL    DEFAULT 0.00,
    paid_date       DATE,
    status          TEXT    DEFAULT 'PENDING' CHECK(status IN ('PENDING','PAID','OVERDUE','PARTIAL')),
    days_late       INTEGER DEFAULT 0,
    FOREIGN KEY (account_id) REFERENCES accounts(account_id)
);

-- ── INDEXES for performance ──────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_txn_account   ON transactions(account_id);
CREATE INDEX IF NOT EXISTS idx_txn_date      ON transactions(txn_date);
CREATE INDEX IF NOT EXISTS idx_txn_status    ON transactions(status);
CREATE INDEX IF NOT EXISTS idx_acc_customer  ON accounts(customer_id);

-- ============================================================
-- SEED DATA
-- ============================================================

-- Categories
INSERT OR IGNORE INTO categories (category_name, category_type) VALUES
('Salary',          'INCOME'),
('Freelance',       'INCOME'),
('Interest Earned', 'INCOME'),
('Groceries',       'EXPENSE'),
('Rent',            'EXPENSE'),
('Utilities',       'EXPENSE'),
('Entertainment',   'EXPENSE'),
('Travel',          'EXPENSE'),
('Healthcare',      'EXPENSE'),
('Shopping',        'EXPENSE'),
('Restaurants',     'EXPENSE'),
('Loan Payment',    'EXPENSE'),
('Transfer In',     'TRANSFER'),
('Transfer Out',    'TRANSFER');

-- Customers
INSERT OR IGNORE INTO customers (full_name, email, phone, date_of_birth, joined_date, credit_limit) VALUES
('Alice Johnson',  'alice@email.com',  '555-0101', '1990-03-15', '2021-01-10', 8000.00),
('Bob Martinez',   'bob@email.com',    '555-0102', '1985-07-22', '2020-06-05', 12000.00),
('Carol White',    'carol@email.com',  '555-0103', '1992-11-30', '2022-03-18', 5000.00),
('David Lee',      'david@email.com',  '555-0104', '1988-05-08', '2019-09-01', 15000.00),
('Emma Brown',     'emma@email.com',   '555-0105', '1995-01-25', '2023-02-14', 3000.00);

-- Accounts
INSERT OR IGNORE INTO accounts (customer_id, account_type, account_number, balance, opened_date) VALUES
(1, 'CHECKING', 'CHK-1001', 4250.75,  '2021-01-10'),
(1, 'SAVINGS',  'SAV-1001', 12000.00, '2021-01-10'),
(2, 'CHECKING', 'CHK-1002', 8900.50,  '2020-06-05'),
(2, 'CREDIT',   'CRD-1002', -2300.00, '2020-06-05'),
(2, 'LOAN',     'LNS-1002', -15000.00,'2021-03-01'),
(3, 'CHECKING', 'CHK-1003', 1200.00,  '2022-03-18'),
(3, 'SAVINGS',  'SAV-1003', 500.00,   '2022-03-18'),
(4, 'CHECKING', 'CHK-1004', 22000.00, '2019-09-01'),
(4, 'SAVINGS',  'SAV-1004', 85000.00, '2019-09-01'),
(5, 'CHECKING', 'CHK-1005', 320.00,   '2023-02-14');

-- Transactions (realistic 6-month history)
INSERT OR IGNORE INTO transactions (account_id, category_id, txn_date, amount, txn_type, description, reference_id, merchant_name, merchant_city, channel, status) VALUES
-- Alice - Regular income & expenses
(1, 1,  '2024-01-01', 5000.00, 'CREDIT', 'Monthly Salary',        'REF-A001', 'Employer Corp',    'New York',    'DIRECT_DEPOSIT', 'COMPLETED'),
(1, 4,  '2024-01-03', 120.50,  'DEBIT',  'Weekly groceries',      'REF-A002', 'Whole Foods',       'New York',    'POS',            'COMPLETED'),
(1, 5,  '2024-01-05', 1500.00, 'DEBIT',  'January Rent',          'REF-A003', 'Property Mgmt',     'New York',    'TRANSFER',       'COMPLETED'),
(1, 11, '2024-01-07', 45.00,   'DEBIT',  'Dinner out',            'REF-A004', 'The Italian Place', 'New York',    'POS',            'COMPLETED'),
(1, 7,  '2024-01-12', 15.99,   'DEBIT',  'Netflix subscription',  'REF-A005', 'Netflix',           'Online',      'ONLINE',         'COMPLETED'),
(1, 1,  '2024-02-01', 5000.00, 'CREDIT', 'Monthly Salary',        'REF-A006', 'Employer Corp',     'New York',    'DIRECT_DEPOSIT', 'COMPLETED'),
(1, 4,  '2024-02-04', 98.30,   'DEBIT',  'Groceries',             'REF-A007', 'Trader Joes',       'New York',    'POS',            'COMPLETED'),
(1, 10, '2024-02-14', 250.00,  'DEBIT',  'Valentines shopping',   'REF-A008', 'Macys',             'New York',    'POS',            'COMPLETED'),
(1, 1,  '2024-03-01', 5000.00, 'CREDIT', 'Monthly Salary',        'REF-A009', 'Employer Corp',     'New York',    'DIRECT_DEPOSIT', 'COMPLETED'),
(1, 8,  '2024-03-10', 800.00,  'DEBIT',  'Flight to Miami',       'REF-A010', 'Delta Airlines',    'Online',      'ONLINE',         'COMPLETED'),

-- Bob - Higher income, credit card usage, loan
(3, 1,  '2024-01-02', 9500.00, 'CREDIT', 'Monthly Salary',        'REF-B001', 'Tech Inc',          'San Francisco','DIRECT_DEPOSIT','COMPLETED'),
(3, 5,  '2024-01-05', 2200.00, 'DEBIT',  'January Rent',          'REF-B002', 'SF Properties',     'San Francisco','TRANSFER',      'COMPLETED'),
(3, 4,  '2024-01-06', 200.00,  'DEBIT',  'Grocery run',           'REF-B003', 'Safeway',           'San Francisco','POS',           'COMPLETED'),
(4, 10, '2024-01-15', 450.00,  'DEBIT',  'New shoes',             'REF-B004', 'Nike Store',        'San Francisco','POS',           'COMPLETED'),
(4, 7,  '2024-01-20', 89.99,   'DEBIT',  'Spotify + Apple Music', 'REF-B005', 'Apple',             'Online',       'ONLINE',        'COMPLETED'),
(3, 1,  '2024-02-02', 9500.00, 'CREDIT', 'Monthly Salary',        'REF-B006', 'Tech Inc',          'San Francisco','DIRECT_DEPOSIT','COMPLETED'),
(4, 12, '2024-02-10', 500.00,  'DEBIT',  'Credit card payment',   'REF-B007', 'VISA Payment',      'Online',       'ONLINE',        'COMPLETED'),
(5, 12, '2024-02-15', 850.00,  'DEBIT',  'Loan installment',      'REF-B008', 'Loan Dept',         'Internal',     'TRANSFER',      'COMPLETED'),
(3, 1,  '2024-03-02', 9500.00, 'CREDIT', 'Monthly Salary',        'REF-B009', 'Tech Inc',          'San Francisco','DIRECT_DEPOSIT','COMPLETED'),

-- Carol - Low balance, struggling finances
(6, 1,  '2024-01-03', 2800.00, 'CREDIT', 'Monthly Salary',        'REF-C001', 'Retail Co',         'Chicago',     'DIRECT_DEPOSIT', 'COMPLETED'),
(6, 5,  '2024-01-05', 1100.00, 'DEBIT',  'Rent',                  'REF-C002', 'Landlord LLC',      'Chicago',     'TRANSFER',       'COMPLETED'),
(6, 4,  '2024-01-08', 180.00,  'DEBIT',  'Groceries',             'REF-C003', 'Aldi',              'Chicago',     'POS',            'COMPLETED'),
(6, 6,  '2024-01-15', 120.00,  'DEBIT',  'Electricity bill',      'REF-C004', 'ComEd',             'Chicago',     'ONLINE',         'COMPLETED'),
(6, 1,  '2024-02-03', 2800.00, 'CREDIT', 'Monthly Salary',        'REF-C005', 'Retail Co',         'Chicago',     'DIRECT_DEPOSIT', 'COMPLETED'),
(6, 9,  '2024-02-20', 350.00,  'DEBIT',  'ER visit copay',        'REF-C006', 'City Hospital',     'Chicago',     'POS',            'COMPLETED'),
(6, 1,  '2024-03-03', 2800.00, 'CREDIT', 'Monthly Salary',        'REF-C007', 'Retail Co',         'Chicago',     'DIRECT_DEPOSIT', 'COMPLETED'),

-- David - High net worth, investments
(8, 1,  '2024-01-02', 18000.00,'CREDIT', 'Monthly Salary',        'REF-D001', 'Finance Corp',      'Boston',      'DIRECT_DEPOSIT', 'COMPLETED'),
(8, 2,  '2024-01-10', 3500.00, 'CREDIT', 'Freelance consulting',  'REF-D002', 'Client A',          'Remote',      'TRANSFER',       'COMPLETED'),
(8, 3,  '2024-01-31', 425.00,  'CREDIT', 'Savings interest',      'REF-D003', 'Bank Interest',     'Internal',    'DIRECT_DEPOSIT', 'COMPLETED'),
(8, 5,  '2024-01-05', 3500.00, 'DEBIT',  'Mortgage payment',      'REF-D004', 'Home Mortgage',     'Boston',      'TRANSFER',       'COMPLETED'),
(8, 1,  '2024-02-02', 18000.00,'CREDIT', 'Monthly Salary',        'REF-D005', 'Finance Corp',      'Boston',      'DIRECT_DEPOSIT', 'COMPLETED'),
(8, 8,  '2024-02-20', 4200.00, 'DEBIT',  'Europe vacation',       'REF-D006', 'Travel Agency',     'Boston',      'ONLINE',         'COMPLETED'),

-- Emma - New customer, thin credit history
(10, 1, '2024-02-14', 2200.00, 'CREDIT', 'First paycheck',        'REF-E001', 'Startup XYZ',       'Austin',      'DIRECT_DEPOSIT', 'COMPLETED'),
(10, 5, '2024-02-16', 900.00,  'DEBIT',  'Rent',                  'REF-E002', 'Austin Rentals',    'Austin',      'TRANSFER',       'COMPLETED'),
(10, 4, '2024-02-18', 85.00,   'DEBIT',  'Groceries',             'REF-E003', 'HEB',               'Austin',      'POS',            'COMPLETED'),
(10, 1, '2024-03-14', 2200.00, 'CREDIT', 'Monthly Salary',        'REF-E004', 'Startup XYZ',       'Austin',      'DIRECT_DEPOSIT', 'COMPLETED'),
(10, 6, '2024-03-20', 75.00,   'DEBIT',  'Internet bill',         'REF-E005', 'AT&T',              'Austin',      'ONLINE',         'COMPLETED');

-- Loan Payment Schedule for Bob's loan (account_id=5)
INSERT OR IGNORE INTO loan_payments (account_id, due_date, amount_due, principal, interest, amount_paid, paid_date, status, days_late) VALUES
(5, '2024-01-15', 850.00, 720.00, 130.00, 850.00, '2024-01-14', 'PAID',    0),
(5, '2024-02-15', 850.00, 726.00, 124.00, 850.00, '2024-02-15', 'PAID',    0),
(5, '2024-03-15', 850.00, 732.00, 118.00, 850.00, '2024-03-18', 'PAID',    3),
(5, '2024-04-15', 850.00, 738.00, 112.00, 850.00, '2024-04-20', 'PAID',    5),
(5, '2024-05-15', 850.00, 744.00, 106.00, 500.00, '2024-05-15', 'PARTIAL', 0),
(5, '2024-06-15', 850.00, 750.00, 100.00,   0.00,  NULL,         'OVERDUE', 15);
