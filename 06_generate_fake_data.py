"""
Step 4: Generate 50 realistic fake customers with accounts,
transactions, and loan history using the Faker library.
Run this AFTER run_project.py to expand the database.
"""

import sqlite3
import os
import random
from datetime import datetime, timedelta
from faker import Faker

fake = Faker()
random.seed(42)

DB_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fintech.db")

ACCOUNT_TYPES    = ['CHECKING', 'SAVINGS', 'CREDIT', 'LOAN']
CHANNELS         = ['ATM', 'ONLINE', 'POS', 'TRANSFER', 'DIRECT_DEPOSIT']
MERCHANT_CITIES  = ['New York', 'Los Angeles', 'Chicago', 'Houston', 'Austin',
                    'San Francisco', 'Seattle', 'Boston', 'Miami', 'Denver']
MERCHANT_COUNTRIES = ['US'] * 18 + ['UK', 'CA']   # mostly US, some foreign

def random_date(start_days_ago, end_days_ago=0):
    start = datetime.now() - timedelta(days=start_days_ago)
    end   = datetime.now() - timedelta(days=end_days_ago)
    delta = end - start
    return (start + timedelta(seconds=random.randint(0, int(delta.total_seconds())))).strftime('%Y-%m-%d')

def random_datetime(start_days_ago, end_days_ago=0):
    start = datetime.now() - timedelta(days=start_days_ago)
    end   = datetime.now() - timedelta(days=end_days_ago)
    delta = end - start
    return (start + timedelta(seconds=random.randint(0, int(delta.total_seconds())))).strftime('%Y-%m-%d %H:%M:%S')

def generate_customers(conn, n=50):
    print(f"  Generating {n} fake customers...")
    cursor = conn.cursor()

    for i in range(n):
        # ── Customer ──────────────────────────────────────────
        dob         = fake.date_of_birth(minimum_age=22, maximum_age=65).strftime('%Y-%m-%d')
        joined      = random_date(2000, 30)
        credit_limit = round(random.choice([2000, 3000, 5000, 8000, 12000, 15000, 20000]), 2)

        cursor.execute("""
            INSERT INTO customers (full_name, email, phone, date_of_birth, joined_date, credit_limit, is_active)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """, (
            fake.name(),
            fake.unique.email(),
            fake.phone_number()[:15],
            dob, joined, credit_limit,
            random.choices([1, 0], weights=[95, 5])[0]
        ))
        customer_id = cursor.lastrowid

        # ── Accounts (1-3 per customer) ───────────────────────
        num_accounts   = random.randint(1, 3)
        chosen_types   = random.sample(ACCOUNT_TYPES, k=min(num_accounts, len(ACCOUNT_TYPES)))
        account_ids    = []

        for acc_type in chosen_types:
            if acc_type == 'CHECKING':
                balance = round(random.uniform(100, 15000), 2)
            elif acc_type == 'SAVINGS':
                balance = round(random.uniform(500, 80000), 2)
            elif acc_type == 'CREDIT':
                balance = round(-random.uniform(0, credit_limit * 0.8), 2)
            else:  # LOAN
                balance = round(-random.uniform(5000, 50000), 2)

            acc_num = f"{acc_type[:3]}-{random.randint(10000, 99999)}-{i}"
            cursor.execute("""
                INSERT INTO accounts (customer_id, account_type, account_number, balance, opened_date, is_active)
                VALUES (?, ?, ?, ?, ?, 1)
            """, (customer_id, acc_type, acc_num, balance, joined))
            account_ids.append((cursor.lastrowid, acc_type))

        # ── Transactions (5-25 per checking/savings account) ──
        income_categories  = [1, 2, 3]   # Salary, Freelance, Interest
        expense_categories = [4, 5, 6, 7, 8, 9, 10, 11, 12]

        for acc_id, acc_type in account_ids:
            if acc_type not in ('CHECKING', 'SAVINGS'):
                continue

            num_txns = random.randint(5, 25)
            monthly_income = random.uniform(2000, 18000)

            for _ in range(num_txns):
                is_credit = random.random() < 0.35
                txn_type  = 'CREDIT' if is_credit else 'DEBIT'
                amount    = round(monthly_income * random.uniform(0.02, 0.4) if is_credit
                                  else random.uniform(10, monthly_income * 0.3), 2)
                category  = random.choice(income_categories if is_credit else expense_categories)
                city      = random.choice(MERCHANT_CITIES)
                country   = random.choice(MERCHANT_COUNTRIES)
                txn_date  = random_datetime(180, 1)
                channel   = 'DIRECT_DEPOSIT' if is_credit else random.choice(CHANNELS[1:])

                cursor.execute("""
                    INSERT INTO transactions
                        (account_id, category_id, txn_date, amount, txn_type,
                         description, merchant_name, merchant_city, merchant_country, channel, status)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'COMPLETED')
                """, (
                    acc_id, category, txn_date, amount, txn_type,
                    fake.bs()[:50], fake.company()[:40], city, country, channel
                ))

        # ── Loan payments (for LOAN accounts) ─────────────────
        for acc_id, acc_type in account_ids:
            if acc_type != 'LOAN':
                continue

            monthly_payment = round(random.uniform(300, 1500), 2)
            for m in range(6):
                due_date   = (datetime.now() - timedelta(days=30 * (6 - m))).strftime('%Y-%m-%d')
                principal  = round(monthly_payment * 0.85, 2)
                interest   = round(monthly_payment * 0.15, 2)
                days_late  = random.choices([0, 0, 0, random.randint(1, 30), random.randint(31, 90)],
                                             weights=[70, 10, 5, 10, 5])[0]
                if m == 5 and random.random() < 0.2:     # last payment sometimes overdue
                    status, paid_amt, paid_date = 'OVERDUE', 0.0, None
                elif days_late > 30:
                    status, paid_amt = 'PARTIAL', round(monthly_payment * 0.5, 2)
                    paid_date = (datetime.strptime(due_date, '%Y-%m-%d') + timedelta(days=days_late)).strftime('%Y-%m-%d')
                else:
                    status, paid_amt = 'PAID', monthly_payment
                    paid_date = (datetime.strptime(due_date, '%Y-%m-%d') + timedelta(days=days_late)).strftime('%Y-%m-%d')

                cursor.execute("""
                    INSERT INTO loan_payments
                        (account_id, due_date, amount_due, principal, interest,
                         amount_paid, paid_date, status, days_late)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (acc_id, due_date, monthly_payment, principal, interest,
                      paid_amt, paid_date, status, days_late))

    conn.commit()
    print(f"  ✓ Done")

if __name__ == '__main__':
    print("=" * 55)
    print("  STEP 4: Generating 50 Fake Customers")
    print("=" * 55)

    if not os.path.exists(DB_PATH):
        print("  ✗ fintech.db not found — run run_project.py first!")
        exit(1)

    conn = sqlite3.connect(DB_PATH)
    conn.execute("PRAGMA foreign_keys = ON")

    before_customers = conn.execute("SELECT COUNT(*) FROM customers").fetchone()[0]
    before_txns      = conn.execute("SELECT COUNT(*) FROM transactions").fetchone()[0]

    generate_customers(conn, n=50)

    after_customers = conn.execute("SELECT COUNT(*) FROM customers").fetchone()[0]
    after_txns      = conn.execute("SELECT COUNT(*) FROM transactions").fetchone()[0]
    after_accounts  = conn.execute("SELECT COUNT(*) FROM accounts").fetchone()[0]
    after_loans     = conn.execute("SELECT COUNT(*) FROM loan_payments").fetchone()[0]

    print(f"\n  Database now contains:")
    print(f"    Customers    : {after_customers}  (+{after_customers - before_customers})")
    print(f"    Accounts     : {after_accounts}")
    print(f"    Transactions : {after_txns}  (+{after_txns - before_txns})")
    print(f"    Loan payments: {after_loans}")

    conn.close()
    print(f"\n  ✓ Saved to: {DB_PATH}")
    print("=" * 55)
