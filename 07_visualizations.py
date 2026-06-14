"""
Step 5: Visualizations using pandas + matplotlib
Generates 6 charts saved as a single dashboard PNG.
Run after run_project.py and 06_generate_fake_data.py
"""

import sqlite3
import os
import pandas as pd
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.gridspec import GridSpec
import warnings
warnings.filterwarnings('ignore')

DB_PATH  = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fintech.db")
OUT_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fintech_dashboard.png")

# ── Color palette ────────────────────────────────────────────
COLORS = {
    'primary'   : '#2563EB',
    'success'   : '#16A34A',
    'danger'    : '#DC2626',
    'warning'   : '#D97706',
    'purple'    : '#7C3AED',
    'gray'      : '#6B7280',
    'light_blue': '#DBEAFE',
    'bg'        : '#F8FAFC',
    'card'      : '#FFFFFF',
}
GRADE_COLORS = {
    'EXCELLENT': '#16A34A',
    'GOOD'     : '#2563EB',
    'FAIR'     : '#D97706',
    'POOR'     : '#DC2626',
}
SEG_COLORS = {
    'HIGH VALUE': '#7C3AED',
    'GROWING'   : '#16A34A',
    'STABLE'    : '#2563EB',
    'AT RISK'   : '#D97706',
    'CHURNED'   : '#DC2626',
}

def load(conn, query):
    return pd.read_sql_query(query, conn)

print("=" * 55)
print("  STEP 5: Generating Fintech Dashboard")
print("=" * 55)

conn = sqlite3.connect(DB_PATH)

ext_sql = os.path.join(os.path.dirname(os.path.abspath(__file__)), "05_extended_features.sql")
if os.path.exists(ext_sql):
    with open(ext_sql) as f:
        conn.executescript(f.read())


# ── Load data ────────────────────────────────────────────────
df_scores = load(conn, """
    SELECT full_name, credit_score, credit_grade,
           payment_score, utilization_score, age_score,
           mix_score, activity_score
    FROM v_credit_scores ORDER BY credit_score DESC
""")

df_cashflow = load(conn, """
    SELECT c.full_name,
           STRFTIME('%Y-%m', t.txn_date) AS month,
           SUM(CASE WHEN t.txn_type='CREDIT' THEN t.amount ELSE 0 END) AS income,
           SUM(CASE WHEN t.txn_type='DEBIT'  THEN t.amount ELSE 0 END) AS expenses
    FROM customers c
    JOIN accounts a ON c.customer_id = a.customer_id
    JOIN transactions t ON a.account_id = t.account_id
    WHERE t.status='COMPLETED' AND c.customer_id <= 5
    GROUP BY c.full_name, STRFTIME('%Y-%m', t.txn_date)
    ORDER BY month
""")

df_categories = load(conn, """
    SELECT cat.category_name, cat.category_type, SUM(t.amount) AS total
    FROM transactions t
    JOIN categories cat ON t.category_id = cat.category_id
    WHERE t.status='COMPLETED' AND t.txn_type='DEBIT'
      AND cat.category_type = 'EXPENSE'
    GROUP BY cat.category_name
    ORDER BY total DESC LIMIT 8
""")

df_segments = load(conn, """
    SELECT segment, COUNT(*) AS count FROM v_customer_segments
    GROUP BY segment ORDER BY count DESC
""")

df_fraud = load(conn, """
    SELECT risk_level, COUNT(*) AS count FROM v_fraud_summary
    GROUP BY risk_level ORDER BY count DESC
""")

df_savings = load(conn, """
    SELECT full_name, month_number,
           projected_balance, interest_earned
    FROM v_savings_projections
    WHERE full_name IN ('Alice Johnson','David Lee','Carol White')
    ORDER BY full_name, month_number
""")

df_grade_dist = load(conn, """
    SELECT credit_grade,
           COUNT(*) AS count,
           ROUND(AVG(credit_score),0) AS avg_score
    FROM v_credit_scores
    GROUP BY credit_grade
    ORDER BY avg_score DESC
""")

conn.close()

# ── Figure layout ────────────────────────────────────────────
fig = plt.figure(figsize=(20, 24), facecolor=COLORS['bg'])
fig.suptitle('Fintech SQL Project — Analytics Dashboard',
             fontsize=26, fontweight='bold', color='#1E293B',
             y=0.98, x=0.5)
fig.text(0.5, 0.965, 'Transaction Ledger  ·  Credit Score Analyzer  ·  Fraud Detection  ·  Customer Segmentation',
         ha='center', fontsize=12, color=COLORS['gray'])

gs = GridSpec(3, 2, figure=fig, hspace=0.42, wspace=0.32,
              left=0.07, right=0.95, top=0.945, bottom=0.04)

# ─── CHART 1: Credit Scores Bar ─────────────────────────────
ax1 = fig.add_subplot(gs[0, 0])
ax1.set_facecolor(COLORS['card'])
top10 = df_scores.head(10)
bar_colors = [GRADE_COLORS.get(g, COLORS['primary']) for g in top10['credit_grade']]
bars = ax1.barh(top10['full_name'], top10['credit_score'],
                color=bar_colors, edgecolor='white', linewidth=0.5, height=0.65)
ax1.set_xlim(250, 870)
ax1.axvline(x=750, color=GRADE_COLORS['EXCELLENT'], linestyle='--', alpha=0.5, linewidth=1.2, label='Excellent (750)')
ax1.axvline(x=670, color=GRADE_COLORS['GOOD'],      linestyle='--', alpha=0.5, linewidth=1.2, label='Good (670)')
ax1.axvline(x=580, color=GRADE_COLORS['FAIR'],      linestyle='--', alpha=0.5, linewidth=1.2, label='Fair (580)')
for bar, score, grade in zip(bars, top10['credit_score'], top10['credit_grade']):
    ax1.text(score + 3, bar.get_y() + bar.get_height()/2,
             f'{int(score)}  {grade}', va='center', fontsize=8.5, fontweight='bold',
             color=GRADE_COLORS.get(grade, COLORS['primary']))
ax1.set_title('Credit Scores — Top 10 Customers', fontsize=13, fontweight='bold', pad=10)
ax1.set_xlabel('Credit Score (300–850)', fontsize=10)
ax1.legend(fontsize=8, loc='lower right')
ax1.invert_yaxis()
ax1.spines[['top','right']].set_visible(False)

# ─── CHART 2: Credit Grade Distribution ─────────────────────
ax2 = fig.add_subplot(gs[0, 1])
ax2.set_facecolor(COLORS['card'])
grades  = df_grade_dist['credit_grade'].tolist()
counts  = df_grade_dist['count'].tolist()
colors2 = [GRADE_COLORS.get(g, COLORS['gray']) for g in grades]
wedges, texts, autotexts = ax2.pie(
    counts, labels=grades, colors=colors2,
    autopct=lambda p: f'{p:.0f}%\n({int(p*sum(counts)/100)})',
    startangle=90, pctdistance=0.75,
    wedgeprops=dict(edgecolor='white', linewidth=2)
)
for t in texts:      t.set_fontsize(11); t.set_fontweight('bold')
for at in autotexts: at.set_fontsize(9);  at.set_color('white'); at.set_fontweight('bold')
ax2.set_title('Credit Grade Distribution\nAll Customers', fontsize=13, fontweight='bold', pad=10)

# ─── CHART 3: Monthly Income vs Expenses (original 5 customers) ──
ax3 = fig.add_subplot(gs[1, 0])
ax3.set_facecolor(COLORS['card'])
palette = [COLORS['primary'], COLORS['success'], COLORS['warning'],
           COLORS['purple'], COLORS['danger']]
for idx, (name, grp) in enumerate(df_cashflow.groupby('full_name')):
    grp = grp.sort_values('month')
    ax3.plot(grp['month'], grp['income'],   color=palette[idx], linewidth=2,   label=f'{name.split()[0]} Income')
    ax3.plot(grp['month'], grp['expenses'], color=palette[idx], linewidth=1.2, linestyle='--', alpha=0.6)
ax3.set_title('Monthly Income (solid) vs Expenses (dashed)\nOriginal 5 Customers', fontsize=13, fontweight='bold', pad=10)
ax3.set_xlabel('Month', fontsize=10)
ax3.set_ylabel('Amount (USD)', fontsize=10)
ax3.legend(fontsize=7.5, ncol=2, loc='upper left')
ax3.tick_params(axis='x', rotation=35, labelsize=8)
ax3.yaxis.set_major_formatter(plt.FuncFormatter(lambda x, _: f'${x:,.0f}'))
ax3.spines[['top','right']].set_visible(False)

# ─── CHART 4: Top Spending Categories ────────────────────────
ax4 = fig.add_subplot(gs[1, 1])
ax4.set_facecolor(COLORS['card'])
cat_colors = plt.cm.Blues(
    [0.9 - i * 0.08 for i in range(len(df_categories))]
)
bars4 = ax4.bar(df_categories['category_name'], df_categories['total'],
                color=cat_colors, edgecolor='white', linewidth=0.5)
for bar, val in zip(bars4, df_categories['total']):
    ax4.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 50,
             f'${val:,.0f}', ha='center', va='bottom', fontsize=8.5, fontweight='bold')
ax4.set_title('Top Spending Categories\n(All Customers, All Time)', fontsize=13, fontweight='bold', pad=10)
ax4.set_ylabel('Total Spent (USD)', fontsize=10)
ax4.tick_params(axis='x', rotation=35, labelsize=9)
ax4.yaxis.set_major_formatter(plt.FuncFormatter(lambda x, _: f'${x:,.0f}'))
ax4.spines[['top','right']].set_visible(False)

# ─── CHART 5: Customer Segmentation ──────────────────────────
ax5 = fig.add_subplot(gs[2, 0])
ax5.set_facecolor(COLORS['card'])
seg_labels = df_segments['segment'].tolist()
seg_counts = df_segments['count'].tolist()
seg_colors = [SEG_COLORS.get(s, COLORS['gray']) for s in seg_labels]
bars5 = ax5.bar(seg_labels, seg_counts, color=seg_colors,
                edgecolor='white', linewidth=0.5, width=0.6)
for bar, cnt in zip(bars5, seg_counts):
    ax5.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 0.3,
             str(cnt), ha='center', va='bottom', fontsize=11, fontweight='bold')
ax5.set_title('Customer Segmentation\n(55 Customers)', fontsize=13, fontweight='bold', pad=10)
ax5.set_ylabel('Number of Customers', fontsize=10)
ax5.tick_params(axis='x', labelsize=10)
legend_patches = [mpatches.Patch(color=v, label=k) for k, v in SEG_COLORS.items()]
ax5.legend(handles=legend_patches, fontsize=8, loc='upper right')
ax5.spines[['top','right']].set_visible(False)

# ─── CHART 6: Savings Projections ────────────────────────────
ax6 = fig.add_subplot(gs[2, 1])
ax6.set_facecolor(COLORS['card'])
proj_palette = [COLORS['primary'], COLORS['success'], COLORS['warning']]
for idx, (name, grp) in enumerate(df_savings.groupby('full_name')):
    grp = grp.sort_values('month_number')
    ax6.plot(grp['month_number'], grp['projected_balance'],
             color=proj_palette[idx], linewidth=2.2, marker='o', markersize=4,
             label=name.split()[0])
    ax6.fill_between(grp['month_number'], grp['projected_balance'],
                     alpha=0.08, color=proj_palette[idx])
ax6.set_title('12-Month Savings Projections\n(3.5% Annual Rate — Compound Monthly)', fontsize=13, fontweight='bold', pad=10)
ax6.set_xlabel('Month', fontsize=10)
ax6.set_ylabel('Projected Balance (USD)', fontsize=10)
ax6.set_xticks(range(1, 13))
ax6.legend(fontsize=9)
ax6.yaxis.set_major_formatter(plt.FuncFormatter(lambda x, _: f'${x:,.0f}'))
ax6.spines[['top','right']].set_visible(False)

# ── Save ─────────────────────────────────────────────────────
plt.savefig(OUT_PATH, dpi=150, bbox_inches='tight',
            facecolor=COLORS['bg'], edgecolor='none')
plt.close()

print(f"  ✓ Dashboard saved to: {OUT_PATH}")
print("=" * 55)
