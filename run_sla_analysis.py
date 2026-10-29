"""Resolution-time / SLA analysis for NYC 311 service requests.

What it does
  1. Loads your cleaned dataset (.xlsx or .csv) into a local SQLite file.
  2. Builds an "observation window" table so closure rates are fair (see sql/00_...).
  3. Runs the SQL scripts in sql/ and saves each result as a CSV in outputs/.
  4. Draws two charts into outputs/charts/.

It also protects you from conclusions the data cannot support:
  * If the data spans fewer than --short-span-days days, the weekday, monthly, and
    average-days-to-close analyses are skipped (they would be biased or meaningless).
  * If due_date is empty, the "closed after due date" analysis is skipped.

Usage
  pip install -r requirements.txt
  python run_sla_analysis.py --input "NYC_311_Master_Dataset(Automation).xlsx"

Options
  --window-hours H       closure window for the "closed within H hours" rate (default 1)
  --batch-gap-hours H    a gap this long between created dates starts a new capture batch (default 6)
  --min-count N          hide groups with fewer than N eligible requests (default 30)
  --short-span-days D    below this many days of data, skip analyses that need a longer window (default 14)
  --db PATH, --out DIR   where to write the SQLite file and the result CSVs

Required columns (any capitalization; spaces or underscores):
  unique_key, created_date, closed_date, agency, complaint_type    (due_date is optional)
"""
import argparse
import re
import sqlite3
import sys
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).parent
SQL_DIR = ROOT / "sql"

REQUIRED = ["unique_key", "created_date", "closed_date", "agency", "complaint_type"]
DATE_COLS = ["created_date", "closed_date", "due_date"]

# If your file uses different column names, add them as  "your name": "standard name".
ALIASES = {
    "request_id": "unique_key",
    "id": "unique_key",
    "created": "created_date",
    "closed": "closed_date",
    "due": "due_date",
    "complaint": "complaint_type",
}

# Scripts that need a longer span of data to mean anything.
NEEDS_LONG_SPAN = {"02", "04", "05", "06", "07"}
NEEDS_DUE_DATE = {"03"}
WEEKDAYS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
TIME_BANDS = ["Night (0-5)", "Morning (6-11)", "Afternoon (12-17)", "Evening (18-23)"]


def normalize_columns(df: pd.DataFrame) -> pd.DataFrame:
    def norm(name):
        name = re.sub(r"[^0-9a-zA-Z]+", "_", str(name).strip().lower()).strip("_")
        return ALIASES.get(name, name)
    df = df.copy()
    df.columns = [norm(c) for c in df.columns]
    return df


def load_data(path: Path) -> pd.DataFrame:
    suffix = path.suffix.lower()
    if suffix in (".xlsx", ".xls"):
        df = pd.read_excel(path)
    elif suffix == ".csv":
        df = pd.read_csv(path, low_memory=False)
    else:
        sys.exit(f"Unsupported file type: {suffix}. Use .xlsx or .csv.")

    df = normalize_columns(df)
    missing = [c for c in REQUIRED if c not in df.columns]
    if missing:
        sys.exit(f"Missing required column(s): {missing}\n"
                 f"Columns found: {list(df.columns)}\n"
                 f"Fix: rename them in your file, or add them to ALIASES at the top of this script.")
    if "due_date" not in df.columns:
        df["due_date"] = pd.NaT

    for col in DATE_COLS:
        before = df[col].notna().sum()
        df[col] = pd.to_datetime(df[col], errors="coerce")
        lost = before - df[col].notna().sum()
        if lost:
            print(f"WARNING: {lost} value(s) in {col} could not be read as dates and were set to empty.")
    return df


def read_sql(path: Path) -> str:
    return path.read_text()


def run_scripts(conn, df, out_dir: Path, args) -> None:
    span_days = (df["created_date"].max() - df["created_date"].min()).total_seconds() / 86400
    short = span_days < args.short_span_days
    due_empty = df["due_date"].isna().all()
    params = {"min_count": args.min_count, "window_hours": args.window_hours,
              "gap_hours": args.batch_gap_hours}

    print(f"Data spans {span_days:.1f} days "
          f"({df['created_date'].min()} to {df['created_date'].max()}).")
    if short:
        print(f"NOTE: under {args.short_span_days} days of data, so the average-days-to-close, weekday, "
              f"time-band and monthly analyses are skipped (they would be biased or meaningless).")
    if due_empty:
        print("NOTE: due_date is empty, so the 'closed after due date' analysis is skipped. "
              "Keep due_date in your cleaning step and pull the data again to run it.")

    conn.execute("CREATE INDEX IF NOT EXISTS idx_key ON service_requests(unique_key)")
    conn.execute("DROP TABLE IF EXISTS observed_requests")

    for sql_file in sorted(SQL_DIR.glob("*.sql")):
        number = sql_file.stem.split("_")[0]
        if number == "00":
            conn.execute(read_sql(sql_file), params)
            conn.commit()
            continue
        if short and number in NEEDS_LONG_SPAN:
            print(f"\n--- skipped {sql_file.name} (data span too short) ---")
            continue
        if due_empty and number in NEEDS_DUE_DATE:
            print(f"\n--- skipped {sql_file.name} (no due_date data) ---")
            continue
        result = pd.read_sql_query(read_sql(sql_file), conn, params=params)
        result.to_csv(out_dir / f"{sql_file.stem}.csv", index=False)
        print(f"\n=== {sql_file.name} ({len(result)} rows) ===")
        print(result.head(15).to_string(index=False) if len(result) else "(no rows)")


def longer_span_tables(df: pd.DataFrame, out_dir: Path, args) -> None:
    """Median days to close and a weekday x time-of-day grid. Only used on longer data."""
    c = df[df["closed_date"].notna() & (df["closed_date"] >= df["created_date"])].drop_duplicates("unique_key").copy()
    c["complaint_type"] = c["complaint_type"].astype(str).str.strip().str.upper()
    c["days_to_close"] = (c["closed_date"] - c["created_date"]).dt.total_seconds() / 86400

    by_type = (c.groupby("complaint_type")["days_to_close"]
                 .agg(requests="count", median_days="median", avg_days="mean").round(2).reset_index())
    by_type = by_type[by_type["requests"] >= args.min_count].sort_values("median_days", ascending=False)
    by_type.to_csv(out_dir / "median_days_by_complaint_type.csv", index=False)

    t = c[c["created_date"].dt.strftime("%H:%M:%S") != "00:00:00"].copy()
    t["time_band"] = pd.cut(t["created_date"].dt.hour, bins=[-1, 5, 11, 17, 23], labels=TIME_BANDS).astype(str)
    t["weekday"] = t["created_date"].dt.day_name()
    grid = (t.groupby(["weekday", "time_band"])["days_to_close"]
              .agg(requests="count", median_days="median").round(2).reset_index())
    grid.loc[grid["requests"] < args.min_count, "median_days"] = pd.NA
    grid["weekday"] = pd.Categorical(grid["weekday"], WEEKDAYS, ordered=True)
    grid["time_band"] = pd.Categorical(grid["time_band"], TIME_BANDS, ordered=True)
    grid.sort_values(["weekday", "time_band"]).to_csv(
        out_dir / "heatmap_median_days_weekday_by_timeband.csv", index=False)
    print("\nSaved median_days_by_complaint_type.csv and heatmap_median_days_weekday_by_timeband.csv")


def make_charts(out_dir: Path, window_hours: float) -> None:
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError:
        print("\nmatplotlib is not installed, so charts were skipped (pip install matplotlib).")
        return

    chart_dir = out_dir / "charts"
    chart_dir.mkdir(exist_ok=True)
    label = f"{window_hours:g} hour" + ("" if window_hours == 1 else "s")
    jobs = [
        ("08_closed_within_window_by_agency.csv", "agency",
         f"Requests closed within {label}, by agency", "closed_within_window_by_agency.png"),
        ("09_closed_within_window_by_complaint_type.csv", "complaint_type",
         f"Requests closed within {label}, by complaint type", "closed_within_window_by_complaint_type.png"),
    ]
    for csv_name, label_col, title, png in jobs:
        path = out_dir / csv_name
        if not path.exists():
            continue
        d = pd.read_csv(path)
        if d.empty:
            continue
        d = d.sort_values("pct_closed_within_window")
        fig, ax = plt.subplots(figsize=(8, max(2.6, 0.5 * len(d) + 1.4)))
        bars = ax.barh(d[label_col], d["pct_closed_within_window"], color="#1F3864")
        for bar, pct, n in zip(bars, d["pct_closed_within_window"], d["eligible_requests"]):
            ax.text(bar.get_width() + 0.8, bar.get_y() + bar.get_height() / 2,
                    f"{pct:.1f}%  (n={n:,})", va="center", fontsize=9)
        ax.set_xlim(0, max(100, d["pct_closed_within_window"].max() + 18) if d["pct_closed_within_window"].max() > 80
                    else d["pct_closed_within_window"].max() * 1.45 + 5)
        ax.set_xlabel("% of eligible requests closed within the window")
        ax.set_title(title, loc="left", fontsize=12, fontweight="bold")
        for side in ("top", "right"):
            ax.spines[side].set_visible(False)
        fig.tight_layout()
        fig.savefig(chart_dir / png, dpi=150)
        plt.close(fig)
    print(f"Charts saved in {chart_dir}/")


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--input", required=True, help="cleaned dataset (.xlsx or .csv)")
    p.add_argument("--db", default=str(ROOT / "data" / "nyc311.db"))
    p.add_argument("--out", default=str(ROOT / "outputs"))
    p.add_argument("--window-hours", type=float, default=1.0)
    p.add_argument("--batch-gap-hours", type=float, default=6.0)
    p.add_argument("--min-count", type=int, default=30)
    p.add_argument("--short-span-days", type=float, default=14.0)
    args = p.parse_args()

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    Path(args.db).parent.mkdir(parents=True, exist_ok=True)

    df = load_data(Path(args.input))
    print(f"Loaded {len(df):,} rows from {args.input}\n")

    conn = sqlite3.connect(args.db)
    df.to_sql("service_requests", conn, if_exists="replace", index=False)
    run_scripts(conn, df, out_dir, args)
    conn.close()

    span_days = (df["created_date"].max() - df["created_date"].min()).total_seconds() / 86400
    if span_days >= args.short_span_days:
        longer_span_tables(df, out_dir, args)
    make_charts(out_dir, args.window_hours)
    print(f"\nDone. Results are in {out_dir}/ (CSV files import straight into Power BI).")


if __name__ == "__main__":
    main()
