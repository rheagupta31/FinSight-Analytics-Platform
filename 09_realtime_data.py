"""
09_realtime_data.py — Real-Time Data Pipeline
==============================================
Pulls live data from:
  - Alpha Vantage  : Real stock prices + intraday trades
  - Coinbase       : Live crypto prices (BTC, ETH, SOL)

Does two things every run:
  1. ADD    : Inserts 200+ new real transactions into the ledger
  2. ENRICH : Updates existing transactions with live market context

Usage:
    python3 09_realtime_data.py --key YOUR_ALPHA_VANTAGE_KEY

Get a free Alpha Vantage key at:
    https://www.alphavantage.co/support/#api-key
"""

import sqlite3
import os
import sys
import json
import time
import random
import argparse
from datetime import datetime, timedelta
from urllib.request import urlopen, Request
from urllib.error import URLError

# ── Config ───────────────────────────────────────────────────
DB_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fintech.db")

STOCKS = ["AAPL", "GOOGL", "MSFT", "AMZN", "TSLA", "NVDA", "META", "JPM", "BAC", "GS"]
CRYPTO = ["BTC", "ETH", "SOL"]

STOCK_MERCHANTS = {
    "AAPL": "Apple Inc", "GOOGL": "Alphabet Inc", "MSFT": "Microsoft Corp",
    "AMZN": "Amazon.com", "TSLA": "Tesla Inc", "NVDA": "NVIDIA Corp",
    "META": "Meta Platforms", "JPM": "JPMorgan Chase", "BAC": "Bank of America",
    "GS": "Goldman Sachs"
}

CRYPTO_MERCHANTS = {"BTC": "Bitcoin Exchange", "ETH": "Ethereum Exchange", "SOL": "Solana Exchange"}


# ── Helpers ──────────────────────────────────────────────────
def fetch_json(url, label=""):
    """Fetch JSON from a URL with basic error handling."""
    try:
        req = Request(url, headers={"User-Agent": "fintech-sql-project/1.0"})
        with urlopen(req, timeout=10) as resp:
            return json.loads(resp.read().decode())
    except URLError as e:
        print(f"  ⚠  Network error fetching {label}: {e}")
        return None
    except Exception as e:
        print(f"  ⚠  Error fetching {label}: {e}")
        return None


def random_past_datetime(days_back=30):
    delta = random.randint(0, days_back * 24 * 60)
    return (datetime.now() - timedelta(minutes=delta)).strftime("%Y-%m-%d %H:%M:%S")


def print_section(title):
    print(f"\n{'='*58}")
    print(f"  {title}")
    print(f"{'='*58}")


# ── Alpha Vantage ────────────────────────────────────────────
class AlphaVantage:
    BASE = "https://www.alphavantage.co/query"

    def __init__(self, api_key):
        self.key = api_key

    def quote(self, symbol):
        """Get latest price quote for a stock."""
        url = f"{self.BASE}?function=GLOBAL_QUOTE&symbol={symbol}&apikey={self.key}"
        data = fetch_json(url, symbol)
        if not data or "Global Quote" not in data:
            return None
        q = data["Global Quote"]
        if not q.get("05. price"):
            return None
        return {
            "symbol"  : symbol,
            "price"   : float(q["05. price"]),
            "change"  : float(q["09. change"]),
            "change_pct": q["10. change percent"].strip("%"),
            "volume"  : int(q["06. volume"]),
            "prev_close": float(q["08. previous close"]),
        }

    def intraday(self, symbol, interval="60min"):
        """Get intraday price series — used to generate realistic trade timestamps."""
        url = (f"{self.BASE}?function=TIME_SERIES_INTRADAY"
               f"&symbol={symbol}&interval={interval}&outputsize=compact&apikey={self.key}")
        data = fetch_json(url, f"{symbol} intraday")
        if not data:
            return []
        key = f"Time Series ({interval})"
        if key not in data:
            return []
        series = data[key]
        result = []
        for ts, vals in list(series.items())[:20]:
            result.append({
                "timestamp": ts,
                "open" : float(vals["1. open"]),
                "high" : float(vals["2. high"]),
                "low"  : float(vals["3. low"]),
                "close": float(vals["4. close"]),
            })
        return result

    def overview(self, symbol):
        """Get company overview — sector, description."""
        url = f"{self.BASE}?function=OVERVIEW&symbol={symbol}&apikey={self.key}"
        data = fetch_json(url, f"{symbol} overview")
        if not data or "Symbol" not in data:
            return None
        return {
            "sector"     : data.get("Sector", "Technology"),
            "industry"   : data.get("Industry", ""),
            "description": data.get("Description", "")[:120],
            "market_cap" : data.get("MarketCapitalization", "N/A"),
            "pe_ratio"   : data.get("PERatio", "N/A"),
        }


# ── Coinbase ─────────────────────────────────────────────────
class Coinbase:
    BASE = "https://api.coinbase.com/v2"

    def spot_price(self, coin):
        """Get current spot price for a crypto asset."""
        url = f"{self.BASE}/prices/{coin}-USD/spot"
        data = fetch_json(url, f"{coin} spot")
        if not data or "data" not in data:
            return None
        return {
            "coin"    : coin,
            "price"   : float(data["data"]["amount"]),
            "currency": data["data"]["currency"],
        }

    def historic_prices(self, coin):
        """Get historic daily prices for last 30 days."""
        url = f"{self.BASE}/prices/{coin}-USD/historic?period=month"
        data = fetch_json(url, f"{coin} historic")
        if not data or "data" not in data or "prices" not in data["data"]:
            return []
        return [
            {"time": p["time"], "price": float(p["price"])}
            for p in data["data"]["prices"][:30]
        ]


# ── Database helpers ─────────────────────────────────────────
def get_customer_accounts(conn):
    """Return list of (account_id, customer_id, account_type, balance) for active checking accounts."""
    return conn.execute("""
        SELECT a.account_id, a.customer_id, a.account_type, a.balance
        FROM accounts a
        JOIN customers c ON a.customer_id = c.customer_id
        WHERE a.account_type IN ('CHECKING', 'SAVINGS')
          AND a.is_active = 1
        ORDER BY RANDOM()
    """).fetchall()


def ensure_category(conn, name, cat_type):
    """Insert category if it doesn't exist, return its id."""
    existing = conn.execute(
        "SELECT category_id FROM categories WHERE category_name = ?", (name,)
    ).fetchone()
    if existing:
        return existing[0]
    conn.execute(
        "INSERT INTO categories (category_name, category_type) VALUES (?, ?)",
        (name, cat_type)
    )
    return conn.execute(
        "SELECT category_id FROM categories WHERE category_name = ?", (name,)
    ).fetchone()[0]


def insert_transaction(conn, account_id, category_id, amount, txn_type,
                       description, merchant, city, country, channel, txn_date):
    conn.execute("""
        INSERT INTO transactions
            (account_id, category_id, txn_date, amount, txn_type,
             description, merchant_name, merchant_city, merchant_country, channel, status)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'COMPLETED')
    """, (account_id, category_id, txn_date, round(amount, 2), txn_type,
          description, merchant, city, country, channel))


def log_run(conn, source, records_added, records_enriched, notes=""):
    conn.execute("""
        CREATE TABLE IF NOT EXISTS api_run_log (
            log_id          INTEGER PRIMARY KEY AUTOINCREMENT,
            run_time        DATETIME DEFAULT (DATETIME('now')),
            data_source     TEXT,
            records_added   INTEGER,
            records_enriched INTEGER,
            notes           TEXT
        )
    """)
    conn.execute("""
        INSERT INTO api_run_log (data_source, records_added, records_enriched, notes)
        VALUES (?, ?, ?, ?)
    """, (source, records_added, records_enriched, notes))


# ── PART 1: ADD new transactions ────────────────────────────
def add_stock_transactions(conn, av, accounts, target=120):
    """Pull intraday data for each stock and insert as investment transactions."""
    print_section("PART 1A — Adding Stock Transactions (Alpha Vantage)")
    cat_id   = ensure_category(conn, "Investments", "EXPENSE")
    div_id   = ensure_category(conn, "Dividends",   "INCOME")
    added    = 0
    quotes   = {}

    for symbol in STOCKS:
        if added >= target:
            break

        print(f"  Fetching {symbol}...", end=" ", flush=True)
        quote = av.quote(symbol)
        if not quote:
            print("skip (no data)")
            continue
        quotes[symbol] = quote
        price = quote["price"]

        # Generate 10-15 realistic trades per stock
        num_trades = random.randint(10, 15)
        account_sample = random.choices(accounts, k=num_trades)

        for acc in account_sample:
            acc_id = acc[0]
            shares = round(random.uniform(0.5, 10), 4)
            amount = round(shares * price * random.uniform(0.97, 1.03), 2)  # slight price variation
            is_buy = random.random() < 0.65   # 65% buys, 35% sells
            txn_type = "DEBIT" if is_buy else "CREDIT"
            action   = "BUY" if is_buy else "SELL"
            txn_date = random_past_datetime(30)

            insert_transaction(
                conn, acc_id,
                cat_id if is_buy else div_id,
                amount, txn_type,
                f"{action} {shares} shares of {symbol} @ ${price:.2f}",
                STOCK_MERCHANTS[symbol], "New York", "US", "ONLINE", txn_date
            )
            added += 1

        print(f"${price:.2f}  +{num_trades} trades")

        # Alpha Vantage free tier: 25 calls/day, ~12s between calls to be safe
        if STOCKS.index(symbol) < len(STOCKS) - 1:
            time.sleep(12)

    conn.commit()
    log_run(conn, "Alpha Vantage - Stocks", added, 0,
            f"Symbols: {list(quotes.keys())}")
    print(f"\n  ✓ Added {added} stock transactions")
    return added, quotes


def add_crypto_transactions(conn, cb, accounts, target=80):
    """Pull live crypto prices and insert as crypto purchase/sale transactions."""
    print_section("PART 1B — Adding Crypto Transactions (Coinbase)")
    cat_id = ensure_category(conn, "Crypto",          "EXPENSE")
    inc_id = ensure_category(conn, "Crypto Sale",     "INCOME")
    added  = 0
    prices = {}

    for coin in CRYPTO:
        print(f"  Fetching {coin}...", end=" ", flush=True)
        spot = cb.spot_price(coin)
        if not spot:
            print("skip")
            continue
        price = spot["price"]
        prices[coin] = price

        # Use historic prices to generate varied transaction amounts
        historic = cb.historic_prices(coin)
        price_pool = [h["price"] for h in historic] if historic else [price]

        num_trades = random.randint(20, 30)
        account_sample = random.choices(accounts, k=num_trades)

        for i, acc in enumerate(account_sample):
            acc_id     = acc[0]
            hist_price = random.choice(price_pool)
            units      = round(random.uniform(0.001, 0.5), 6)
            amount     = round(units * hist_price, 2)
            is_buy     = random.random() < 0.6
            txn_type   = "DEBIT" if is_buy else "CREDIT"
            action     = "BUY" if is_buy else "SELL"
            txn_date   = random_past_datetime(30)

            insert_transaction(
                conn, acc_id,
                cat_id if is_buy else inc_id,
                amount, txn_type,
                f"{action} {units} {coin} @ ${hist_price:,.2f}",
                CRYPTO_MERCHANTS[coin], "Online", "US", "ONLINE", txn_date
            )
            added += 1

        print(f"${price:,.2f}  +{num_trades} trades")

    conn.commit()
    log_run(conn, "Coinbase - Crypto", added, 0,
            f"Coins: {list(prices.keys())}, Prices: {prices}")
    print(f"\n  ✓ Added {added} crypto transactions")
    return added, prices


# ── PART 2: ENRICH existing transactions ────────────────────
def enrich_with_market_context(conn, quotes, crypto_prices):
    """
    Add market context to existing transactions:
    - Tag transactions on high-volatility stock days
    - Add a market_notes column with live price context
    """
    print_section("PART 2 — Enriching Existing Transactions")

    # Add market_notes column if it doesn't exist
    try:
        conn.execute("ALTER TABLE transactions ADD COLUMN market_notes TEXT")
        conn.commit()
        print("  Added market_notes column to transactions")
    except Exception:
        pass  # column already exists

    enriched = 0

    # Enrich investment/crypto transactions with current market price delta
    for symbol, quote in quotes.items():
        change = float(quote["change_pct"])
        direction = "↑" if change > 0 else "↓"
        note = f"{symbol} live: ${quote['price']:.2f} ({direction}{abs(change):.2f}% today)"

        result = conn.execute("""
            UPDATE transactions
            SET market_notes = ?
            WHERE merchant_name = ?
              AND market_notes IS NULL
        """, (note, STOCK_MERCHANTS[symbol]))
        enriched += result.rowcount

    # Enrich crypto transactions
    for coin, price in crypto_prices.items():
        note = f"{coin} live spot: ${price:,.2f} USD"
        result = conn.execute("""
            UPDATE transactions
            SET market_notes = ?
            WHERE merchant_name = ?
              AND market_notes IS NULL
        """, (note, CRYPTO_MERCHANTS[coin]))
        enriched += result.rowcount

    # Flag high-spend days relative to stock market drops
    volatile_symbols = [s for s, q in quotes.items() if abs(float(q["change_pct"])) > 1.5]
    if volatile_symbols:
        note = f"High market volatility day — {', '.join(volatile_symbols)} moved >1.5%"
        result = conn.execute("""
            UPDATE transactions
            SET market_notes = ?
            WHERE DATE(txn_date) = DATE('now')
              AND txn_type = 'DEBIT'
              AND amount > 500
              AND market_notes IS NULL
        """, (note,))
        enriched += result.rowcount

    conn.commit()
    log_run(conn, "Enrichment", 0, enriched, f"Volatile: {volatile_symbols}")
    print(f"  ✓ Enriched {enriched} transactions with live market context")
    return enriched


# ── SUMMARY ──────────────────────────────────────────────────
def print_summary(conn, total_added, total_enriched, quotes, crypto_prices):
    print_section("LIVE MARKET SNAPSHOT")

    print("\n  📈 Stocks (Alpha Vantage):")
    for symbol, q in quotes.items():
        arrow = "▲" if q["change"] > 0 else "▼"
        print(f"     {symbol:<6}  ${q['price']:>10.2f}   {arrow} {abs(q['change']):.2f}  ({q['change_pct']}%)")

    print("\n  🪙 Crypto (Coinbase):")
    for coin, price in crypto_prices.items():
        print(f"     {coin:<6}  ${price:>12,.2f}")

    print_section("RUN SUMMARY")
    total_txns = conn.execute("SELECT COUNT(*) FROM transactions").fetchone()[0]
    total_cust = conn.execute("SELECT COUNT(*) FROM customers").fetchone()[0]
    print(f"  Transactions added   : {total_added}")
    print(f"  Transactions enriched: {total_enriched}")
    print(f"  Total transactions   : {total_txns}")
    print(f"  Total customers      : {total_cust}")

    print("\n  Recent API run log:")
    rows = conn.execute("""
        SELECT run_time, data_source, records_added, records_enriched
        FROM api_run_log ORDER BY log_id DESC LIMIT 5
    """).fetchall()
    for r in rows:
        print(f"     {r[0]}  |  {r[1]:<30}  +{r[2]} added  ~{r[3]} enriched")


# ── MAIN ─────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(description="Fintech real-time data pipeline")
    parser.add_argument("--key", required=True,
                        help="Your Alpha Vantage API key (get free at alphavantage.co)")
    parser.add_argument("--stocks-only", action="store_true",
                        help="Only pull stock data, skip crypto")
    parser.add_argument("--crypto-only", action="store_true",
                        help="Only pull crypto data, skip stocks")
    args = parser.parse_args()

    if not os.path.exists(DB_PATH):
        print("✗  fintech.db not found — run run_project.py first!")
        sys.exit(1)

    print("=" * 58)
    print("  FINTECH REAL-TIME DATA PIPELINE")
    print(f"  {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 58)
    print(f"  Database : {DB_PATH}")
    print(f"  Mode     : Both (add new + enrich existing)")
    print(f"  Target   : 200+ transactions per run")

    conn    = sqlite3.connect(DB_PATH)
    conn.execute("PRAGMA foreign_keys = ON")
    accounts = get_customer_accounts(conn)

    if not accounts:
        print("✗  No active accounts found in database.")
        conn.close()
        sys.exit(1)

    av = AlphaVantage(args.key)
    cb = Coinbase()

    total_added    = 0
    total_enriched = 0
    quotes         = {}
    crypto_prices  = {}

    # Part 1A — Stocks
    if not args.crypto_only:
        added, quotes = add_stock_transactions(conn, av, accounts, target=130)
        total_added += added

    # Part 1B — Crypto
    if not args.stocks_only:
        added, crypto_prices = add_crypto_transactions(conn, cb, accounts, target=80)
        total_added += added

    # Part 2 — Enrich
    if quotes or crypto_prices:
        total_enriched = enrich_with_market_context(conn, quotes, crypto_prices)

    print_summary(conn, total_added, total_enriched, quotes, crypto_prices)

    conn.close()
    print(f"\n  ✓  Done. Run python3 07_visualizations.py to refresh the dashboard.")
    print("=" * 58)


if __name__ == "__main__":
    main()
