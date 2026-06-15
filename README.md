# FinSight Analytics Platform

> An end-to-end financial data engineering project simulating a production-grade bank infrastructure — featuring real-time market data ingestion, FICO-style credit scoring, and a rule-based fraud detection engine, all built in SQL and Python.

![SQL](https://img.shields.io/badge/SQL-SQLite%20%7C%20PostgreSQL-blue?style=flat-square&logo=sqlite)
![Python](https://img.shields.io/badge/Python-3.8%2B-yellow?style=flat-square&logo=python)
![Pandas](https://img.shields.io/badge/Pandas-2.0%2B-green?style=flat-square&logo=pandas)
![Matplotlib](https://img.shields.io/badge/Matplotlib-Visualization-orange?style=flat-square)
![Status](https://img.shields.io/badge/Status-Active-brightgreen?style=flat-square)

---

## Description

FinSight Analytics Platform models the core data infrastructure of a real financial institution — from double-entry bookkeeping and credit risk assessment to live fraud detection and real-time market data ingestion via the Alpha Vantage and Coinbase APIs. It is designed as a portfolio-grade project that demonstrates end-to-end SQL and data engineering skills relevant to fintech and big tech roles.

---

## Features

- **Double-entry transaction ledger** — normalized schema modeling real bank account structures across CHECKING, SAVINGS, CREDIT, and LOAN account types
- **FICO-style credit scoring engine** — five-factor weighted scoring system (300–850 scale) implemented entirely in SQL views, covering payment history, credit utilization, account age, credit mix, and recent activity
- **Rule-based fraud detection** — five detection algorithms flagging velocity fraud, large transactions, foreign activity, account drain, and dormant account reactivation
- **Real-time market data pipeline** — live ingestion of stock prices (Alpha Vantage) and cryptocurrency spot prices (Coinbase) with automatic transaction enrichment
- **Analytics dashboard** — six-panel matplotlib visualization covering credit scores, cash flow trends, spending categories, customer segmentation, loan health, and 12-month savings projections

---

## Project Status

### Completed

- [x] Transaction ledger schema with seed data (5 customers, 10 accounts, 40+ transactions)
- [x] FICO-style credit score analyzer across 5 weighted factors
- [x] Fraud detection engine with 5 rule-based algorithms and a combined risk dashboard
- [x] Extended features — monthly trend report, compound interest calculator (recursive CTE), customer segmentation
- [x] 5 interview-style SQL practice queries with full solutions
- [x] Fake data generator using Faker (50 customers, 800+ transactions)
- [x] Real-time data pipeline — Alpha Vantage (10 stocks) + Coinbase (BTC, ETH, SOL)
- [x] 6-panel analytics dashboard via pandas and matplotlib
- [x] PostgreSQL migration guide with syntax translation reference
- [x] GitHub repository with structured commit history

### Planned

- [ ] dbt models for incremental transformation layer
- [ ] Airflow DAG for scheduled pipeline runs
- [ ] Interactive Chart.js dashboard hosted on GitHub Pages
- [ ] BigQuery migration for cloud-scale analytics

---

## Tech Stack

| Layer | Technology |
|---|---|
| Database | SQLite (local), PostgreSQL (production) |
| Language | Python 3.8+ |
| Data manipulation | pandas |
| Visualization | matplotlib |
| Fake data generation | Faker |
| Stock market data | Alpha Vantage API |
| Crypto market data | Coinbase API |
| Version control | Git, GitHub |

---

## Installation

### Prerequisites

```bash
pip install faker pandas matplotlib psycopg2-binary
```

### Clone the repository

```bash
git clone https://github.com/rheagupta31/FinSight-Analytics-Platform.git
cd FinSight-Analytics-Platform
```

### Get a free Alpha Vantage API key

Sign up at [alphavantage.co](https://www.alphavantage.co/support/#api-key) — takes 30 seconds, no credit card required. Store it as an environment variable:

```bash
export ALPHA_VANTAGE_KEY="your_key_here"
```

---

## Usage

Run the scripts in the following order:

### Step 1 — Build the database

```bash
python3 run_project.py
```

Creates `fintech.db` with all tables, views, seed data, and runs all SQL layers. Output includes credit scores, fraud flags, and a combined customer risk dashboard printed to the terminal.

### Step 2 — Ingest real-time market data

```bash
python3 09_realtime_data.py --key $ALPHA_VANTAGE_KEY
```

Pulls live prices for 10 stocks and 3 crypto assets, inserts 200+ real transactions into the ledger, and enriches existing transactions with live market context. Optional flags:

```bash
python3 09_realtime_data.py --key $ALPHA_VANTAGE_KEY --stocks-only
python3 09_realtime_data.py --key $ALPHA_VANTAGE_KEY --crypto-only
```

### Step 3 — Generate the analytics dashboard

```bash
python3 07_visualizations.py
```

Outputs `fintech_dashboard.png` — a 6-panel chart covering credit scores, cash flow trends, spending categories, customer segmentation, loan health, and savings projections.

### Optional — Explore interactively

Open `fintech.db` in [DB Browser for SQLite](https://sqlitebrowser.org) to run custom queries against live data.

### Optional — Migrate to PostgreSQL

```bash
psql -U postgres -c "CREATE DATABASE finsight_db;"
psql -U postgres -d finsight_db -f 08_postgresql_migration.sql
```

---

## Project Structure

```
FinSight-Analytics-Platform/
├── run_project.py                  Main runner — builds DB and prints all results
├── 01_transaction_ledger.sql       Layer 1: Double-entry bookkeeping schema + seed data
├── 02_credit_score_analyzer.sql    Layer 2: FICO-style credit scoring views
├── 03_fraud_detection.sql          Layer 3: Rule-based fraud detection engine
├── 04_practice_queries.sql         5 interview-style SQL challenges with solutions
├── 05_extended_features.sql        Monthly trends, interest calculator, segmentation
├── 06_generate_fake_data.py        Generates realistic customers using Faker
├── 07_visualizations.py            6-panel analytics dashboard (pandas + matplotlib)
├── 08_postgresql_migration.sql     PostgreSQL schema and migration reference
├── 09_realtime_data.py             Real-time Alpha Vantage + Coinbase data pipeline
└── fintech_dashboard.png           Auto-generated analytics output
```

---

## SQL Concepts Demonstrated

| Concept | Where Used |
|---|---|
| Schema design and normalization | Layer 1 |
| Foreign keys, CHECK constraints, indexes | Layer 1 |
| Aggregations — SUM, AVG, COUNT, MIN, MAX | All layers |
| GROUP BY and HAVING | Layers 1–3 |
| CASE WHEN, COALESCE, NULLIF | Layers 2–3 |
| SQL views | Layers 2–3 |
| Window functions — RANK, DENSE_RANK, LAG | Layers 2–3, extended |
| Correlated subqueries | Layer 3 |
| EXISTS and NOT EXISTS | Layer 3 |
| Recursive CTEs | Extended features |
| Date and time functions | All layers |
| Self-joins | Layer 3 |

---

## Sample Output

Running `run_project.py` produces a terminal output including:

```
Customer Risk Dashboard — Loan Decisions
+---------------+--------------+--------------+------------------+-------------+---------------+
| full_name     | credit_score | credit_grade | fraud_risk_level | fraud_flags | loan_decision |
+---------------+--------------+--------------+------------------+-------------+---------------+
| David Lee     | 755          | EXCELLENT    | CLEAN            | 0           | APPROVED      |
| Alice Johnson | 755          | EXCELLENT    | MEDIUM RISK      | 1           | APPROVED      |
| Carol White   | 743          | GOOD         | CLEAN            | 0           | APPROVED      |
| Bob Martinez  | 678          | GOOD         | CLEAN            | 0           | APPROVED      |
+---------------+--------------+--------------+------------------+-------------+---------------+
```

---

## Contributing

This is a personal portfolio project. Feedback, suggestions, and bug reports are welcome via GitHub Issues. If you find it useful as a learning resource, feel free to fork it and adapt it for your own portfolio.

---

## License

This project is licensed under the MIT License.

---

## Author

**Rhea Gupta**
- GitHub: [@rheagupta31](https://github.com/rheagupta31)
- Project: [FinSight Analytics Platform](https://github.com/rheagupta31/FinSight-Analytics-Platform)

---

*Built to demonstrate SQL and data engineering proficiency in a fintech context — from raw schema design through real-time market data ingestion, credit risk modeling, fraud detection, and analytics.*
