import sqlite3
import pandas as pd
from pathlib import Path
import matplotlib.pyplot as plt
import seaborn as sns

# ----------------------------
# CONFIG
# ----------------------------
DB_PATH = Path("/Users/sit/Library/CloudStorage/OneDrive-ThammasatUniversity/Studying/Project/Sale/Data.db")
TABLE_NAME = "transactions_final"


# ----------------------------
# 1) LOAD DATA
# ----------------------------
def load_data(db_path: Path, table_name: str = TABLE_NAME) -> pd.DataFrame:
    conn = sqlite3.connect(db_path)
    df = pd.read_sql(f"SELECT * FROM {table_name};", conn)
    conn.close()
    return df


# ----------------------------
# 2) DATA PREPARATION + FEATURING
# ----------------------------
def prepare_sales_data(df: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    df = df.copy()

    # ---------- data type ----------
    df["transaction_date"] = pd.to_datetime(df["transaction_date"], errors="coerce")
    df["unit_price"] = pd.to_numeric(df["unit_price"], errors="coerce")
    df["quantity"] = pd.to_numeric(df["quantity"], errors="coerce")
    df["discount"] = pd.to_numeric(df["discount"], errors="coerce")
    df["line_total"] = pd.to_numeric(df["line_total"], errors="coerce")

    # ---------- drop rows that are unusable for sales analysis ----------
    df = df.dropna(subset=["transaction_date", "invoice_id", "unit_price", "quantity", "discount", "line_total"])

    # ---------- base sales metrics ----------
    df["gross_sales"] = df["unit_price"] * df["quantity"]
    df["discount_amount"] = df["gross_sales"] * df["discount"]

    # Revenue after discount, with return handling
    df["revenue"] = df["line_total"]
    df["revenue"] = df.apply(
        lambda x: -abs(x["revenue"]) if str(x["transaction_type"]).strip().lower() == "return" else abs(x["revenue"]),
        axis=1
    )

    # ---------- time features ----------
    df["year"] = df["transaction_date"].dt.year
    df["month"] = df["transaction_date"].dt.to_period("M").astype(str)
    df["quarter"] = df["transaction_date"].dt.to_period("Q").astype(str)
    df["day"] = df["transaction_date"].dt.day
    df["weekday"] = df["transaction_date"].dt.day_name()
    df["is_weekend"] = df["weekday"].isin(["Saturday", "Sunday"])

    # ---------- sales direction ----------
    df["is_return"] = df["transaction_type"].astype(str).str.lower().eq("return")

    # ---------- price segment ----------
    # ใช้ qcut ถ้า distribution ใช้ได้, ถ้า error ค่อย fallback เป็น cut
    try:
        df["price_segment"] = pd.qcut(
            df["unit_price"],
            q=4,
            labels=["Low Price", "Mid Price", "High Price", "Premium Price"],
            duplicates="drop"
        )
    except ValueError:
        df["price_segment"] = pd.cut(
            df["unit_price"],
            bins=4,
            labels=["Low Price", "Mid Price", "High Price", "Premium Price"]
        )

    # ---------- discount segment ----------
    df["discount_group"] = pd.cut(
        df["discount"],
        bins=[-0.0001, 0, 0.1, 0.3, 0.5, 1],
        labels=["No Discount", "Low", "Medium", "High", "Very High"]
    )

    # ---------- invoice-level / basket-level featuring ----------
    invoice_summary = df.groupby("invoice_id").agg(
        order_date=("transaction_date", "min"),
        order_revenue=("revenue", "sum"),
        order_gross_sales=("gross_sales", "sum"),
        order_discount_amount=("discount_amount", "sum"),
        order_quantity=("quantity", "sum"),
        line_count=("line_no", "nunique"),
        unique_products=("product_id", "nunique"),
        unique_customers=("customer_id", "nunique"),
        has_return=("is_return", "max")
    ).reset_index()

    # average item value before sign effect
    invoice_summary["avg_item_per_order"] = (
        invoice_summary["order_quantity"].where(invoice_summary["order_quantity"] != 0)
    )
    invoice_summary["avg_item_per_order"] = invoice_summary["order_revenue"] / invoice_summary["avg_item_per_order"]

    # basket size group
    invoice_summary["basket_size_group"] = pd.cut(
        invoice_summary["order_quantity"],
        bins=[0, 1, 3, 5, 10, invoice_summary["order_quantity"].max()],
        labels=["1 item", "2-3 items", "4-5 items", "6-10 items", "10+ items"],
        include_lowest=True
    )

    # order value group
    try:
        invoice_summary["order_value_group"] = pd.qcut(
            invoice_summary["order_revenue"],
            q=4,
            labels=["Low Value", "Mid Value", "High Value", "Very High Value"],
            duplicates="drop"
        )
    except ValueError:
        invoice_summary["order_value_group"] = pd.cut(
            invoice_summary["order_revenue"],
            bins=4,
            labels=["Low Value", "Mid Value", "High Value", "Very High Value"]
        )

    # ---------- weekday order ----------
    weekday_order = [
        "Monday", "Tuesday", "Wednesday", "Thursday",
        "Friday", "Saturday", "Sunday"
    ]
    df["weekday"] = pd.Categorical(df["weekday"], categories=weekday_order, ordered=True)

    return df, invoice_summary


# ----------------------------
# 3) SALES OVERVIEW
# ----------------------------
def sales_overview(df: pd.DataFrame, invoice_summary: pd.DataFrame) -> None:
    total_revenue = df["revenue"].sum()
    total_gross_sales = df["gross_sales"].sum()
    total_discount_amount = df["discount_amount"].sum()
    total_orders = invoice_summary["invoice_id"].nunique()
    total_units = df["quantity"].sum()
    total_returns = df["is_return"].sum()

    aov = total_revenue / total_orders if total_orders else 0
    avg_revenue_per_unit = total_revenue / total_units if total_units else 0
    avg_items_per_order = invoice_summary["order_quantity"].mean() if total_orders else 0

    print("\n===== SALES OVERVIEW =====")
    print(f"Total Revenue: {total_revenue:,.2f}")
    print(f"Gross Sales (Before Discount): {total_gross_sales:,.2f}")
    print(f"Total Discount Amount: {total_discount_amount:,.2f}")
    print(f"Total Orders: {total_orders:,}")
    print(f"Total Quantity: {total_units:,.0f}")
    print(f"Returned Rows: {total_returns:,}")
    print(f"AOV (Average Order Value): {aov:,.2f}")
    print(f"Average Revenue per Unit: {avg_revenue_per_unit:,.2f}")
    print(f"Average Items per Order: {avg_items_per_order:,.2f}")


# ----------------------------
# 4) MONTHLY TREND
# ----------------------------
def monthly_sales_trend(df: pd.DataFrame) -> None:
    trend = df.groupby("month", as_index=False)["revenue"].sum()

    print("\n===== MONTHLY SALES TREND =====")
    print(trend)

    plt.figure(figsize=(12, 5))
    plt.plot(trend["month"], trend["revenue"], marker="o")
    plt.title("Monthly Revenue Trend")
    plt.xlabel("Month")
    plt.ylabel("Revenue")
    plt.xticks(rotation=45)
    plt.tight_layout()
    plt.show()


# ----------------------------
# 5) QUARTERLY TREND
# ----------------------------
def quarterly_sales_trend(df: pd.DataFrame) -> None:
    qtrend = df.groupby("quarter", as_index=False)["revenue"].sum()

    print("\n===== QUARTERLY SALES TREND =====")
    print(qtrend)

    plt.figure(figsize=(8, 5))
    plt.bar(qtrend["quarter"], qtrend["revenue"])
    plt.title("Quarterly Revenue Trend")
    plt.xlabel("Quarter")
    plt.ylabel("Revenue")
    plt.tight_layout()
    plt.show()


# ----------------------------
# 6) REVENUE DRIVER ANALYSIS
# ----------------------------
def revenue_driver_analysis(df: pd.DataFrame) -> None:
    driver_cols = ["revenue", "gross_sales", "quantity", "unit_price", "discount", "discount_amount"]
    corr = df[driver_cols].corr()

    print("\n===== REVENUE DRIVER CORRELATION =====")
    print(corr)

    plt.figure(figsize=(7, 5))
    sns.heatmap(corr, annot=True, cmap="coolwarm", fmt=".2f")
    plt.title("Revenue Driver Correlation")
    plt.tight_layout()
    plt.show()


# ----------------------------
# 7) SALES EFFICIENCY
# ----------------------------
def sales_efficiency(invoice_summary: pd.DataFrame) -> None:
    order_stats = invoice_summary[[
        "order_revenue", "order_quantity", "unique_products", "line_count"
    ]].describe()

    print("\n===== SALES EFFICIENCY =====")
    print(order_stats)

    plt.figure(figsize=(8, 5))
    plt.hist(invoice_summary["order_revenue"], bins=50)
    plt.title("Order Revenue Distribution")
    plt.xlabel("Order Revenue")
    plt.ylabel("Frequency")
    plt.tight_layout()
    plt.show()


# ----------------------------
# 8) BASKET ANALYSIS
# ----------------------------
def basket_analysis(invoice_summary: pd.DataFrame) -> None:
    basket_summary = invoice_summary.groupby("basket_size_group", dropna=False).agg(
        orders=("invoice_id", "nunique"),
        revenue=("order_revenue", "sum"),
        avg_order_value=("order_revenue", "mean"),
        avg_unique_products=("unique_products", "mean")
    ).reset_index()

    print("\n===== BASKET ANALYSIS =====")
    print(basket_summary)

    plt.figure(figsize=(8, 5))
    sns.barplot(data=basket_summary, x="basket_size_group", y="revenue")
    plt.title("Revenue by Basket Size Group")
    plt.xlabel("Basket Size Group")
    plt.ylabel("Revenue")
    plt.tight_layout()
    plt.show()


# ----------------------------
# 9) WEEKDAY ANALYSIS
# ----------------------------
def weekday_sales_analysis(df: pd.DataFrame) -> None:
    weekday_summary = df.groupby("weekday", as_index=False).agg(
        revenue=("revenue", "sum"),
        quantity=("quantity", "sum"),
        orders=("invoice_id", "nunique")
    )

    print("\n===== WEEKDAY SALES ANALYSIS =====")
    print(weekday_summary)

    plt.figure(figsize=(10, 5))
    sns.barplot(data=weekday_summary, x="weekday", y="revenue")
    plt.title("Revenue by Weekday")
    plt.xlabel("Weekday")
    plt.ylabel("Revenue")
    plt.xticks(rotation=30)
    plt.tight_layout()
    plt.show()


# ----------------------------
# 10) WEEKEND VS WEEKDAY
# ----------------------------
def weekend_vs_weekday_analysis(df: pd.DataFrame) -> None:
    summary = df.groupby("is_weekend", as_index=False).agg(
        revenue=("revenue", "sum"),
        orders=("invoice_id", "nunique"),
        quantity=("quantity", "sum")
    )

    summary["day_type"] = summary["is_weekend"].map({False: "Weekday", True: "Weekend"})

    print("\n===== WEEKEND VS WEEKDAY =====")
    print(summary[["day_type", "revenue", "orders", "quantity"]])

    plt.figure(figsize=(6, 5))
    sns.barplot(data=summary, x="day_type", y="revenue")
    plt.title("Revenue: Weekday vs Weekend")
    plt.xlabel("Day Type")
    plt.ylabel("Revenue")
    plt.tight_layout()
    plt.show()


# ----------------------------
# 11) PRICE SEGMENT ANALYSIS
# ----------------------------
def price_segment_analysis(df: pd.DataFrame) -> None:
    summary = df.groupby("price_segment", dropna=False).agg(
        revenue=("revenue", "sum"),
        quantity=("quantity", "sum"),
        orders=("invoice_id", "nunique"),
        avg_unit_price=("unit_price", "mean")
    ).reset_index()

    print("\n===== PRICE SEGMENT ANALYSIS =====")
    print(summary)

    plt.figure(figsize=(8, 5))
    sns.barplot(data=summary, x="price_segment", y="revenue")
    plt.title("Revenue by Price Segment")
    plt.xlabel("Price Segment")
    plt.ylabel("Revenue")
    plt.tight_layout()
    plt.show()


# ----------------------------
# 12) RETURN ANALYSIS
# ----------------------------
def return_analysis(df: pd.DataFrame, invoice_summary: pd.DataFrame) -> None:
    return_rows = df["is_return"].sum()
    total_rows = len(df)
    return_row_rate = return_rows / total_rows if total_rows else 0

    return_orders = invoice_summary["has_return"].sum()
    total_orders = len(invoice_summary)
    return_order_rate = return_orders / total_orders if total_orders else 0

    return_revenue = df.loc[df["is_return"], "revenue"].sum()

    print("\n===== RETURN ANALYSIS =====")
    print(f"Return Row Count: {return_rows:,}")
    print(f"Return Row Rate: {return_row_rate:.2%}")
    print(f"Orders with Return: {return_orders:,}")
    print(f"Order-level Return Rate: {return_order_rate:.2%}")
    print(f"Revenue Impact from Returns: {return_revenue:,.2f}")


# ----------------------------
# 13) SALES STORY / KEY INSIGHTS
# ----------------------------
def sales_insight_summary(df: pd.DataFrame, invoice_summary: pd.DataFrame) -> None:
    total_revenue = df["revenue"].sum()
    total_orders = invoice_summary["invoice_id"].nunique()
    aov = total_revenue / total_orders if total_orders else 0

    month_summary = df.groupby("month", as_index=False)["revenue"].sum()
    peak_month = month_summary.loc[month_summary["revenue"].idxmax()]
    lowest_month = month_summary.loc[month_summary["revenue"].idxmin()]

    corr = df[["revenue", "quantity", "unit_price", "discount"]].corr()

    print("\n===== SALES INSIGHT SUMMARY =====")
    print(f"- Business generated total revenue of {total_revenue:,.2f} from {total_orders:,} orders.")
    print(f"- Average order value (AOV) is {aov:,.2f}, suggesting a relatively low-ticket retail model.")
    print(f"- Peak month: {peak_month['month']} with revenue {peak_month['revenue']:,.2f}")
    print(f"- Lowest month: {lowest_month['month']} with revenue {lowest_month['revenue']:,.2f}")
    print(f"- Revenue has stronger correlation with unit_price ({corr.loc['revenue', 'unit_price']:.2f}) than quantity ({corr.loc['revenue', 'quantity']:.2f}).")
    print(f"- Discount shows a negative correlation with revenue ({corr.loc['revenue', 'discount']:.2f}), indicating potential revenue dilution when discounting increases.")


# ----------------------------
# 14) MAIN SALES ANALYSIS
# ----------------------------
def sales_analysis(df: pd.DataFrame) -> pd.DataFrame:
    df, invoice_summary = prepare_sales_data(df)

    sales_overview(df, invoice_summary)
    monthly_sales_trend(df)
    quarterly_sales_trend(df)
    revenue_driver_analysis(df)
    sales_efficiency(invoice_summary)
    basket_analysis(invoice_summary)
    weekday_sales_analysis(df)
    weekend_vs_weekday_analysis(df)
    price_segment_analysis(df)
    return_analysis(df, invoice_summary)
    sales_insight_summary(df, invoice_summary)

    return df


# ----------------------------
# CUSTOMER DATA PREPARATION
# ----------------------------
def prepare_customer_data(df: pd.DataFrame):

    if "revenue" not in df.columns:
        df, _ = prepare_sales_data(df)

    conn = sqlite3.connect(DB_PATH)
    customer_df = pd.read_sql("SELECT * FROM customers_final;", conn)
    conn.close()

    # merge transaction + customer
    df = df.merge(customer_df, on="customer_id", how="left")

    # customer-level summary
    customer_summary = df.groupby("customer_id").agg(
        customer_revenue=("revenue", "sum"),
        customer_orders=("invoice_id", "nunique"),
        first_purchase=("transaction_date", "min"),
        last_purchase=("transaction_date", "max")
    ).reset_index()

    # AOV
    customer_summary["customer_AOV"] = (
        customer_summary["customer_revenue"] / customer_summary["customer_orders"]
    )

    # segmentation
    customer_summary["customer_segment"] = pd.qcut(
        customer_summary["customer_revenue"],
        q=4,
        labels=["Low", "Mid", "High", "VIP"],
        duplicates="drop"
    )

    # new vs returning
    first_map = customer_summary.set_index("customer_id")["first_purchase"]
    df["first_purchase"] = df["customer_id"].map(first_map)

    df["customer_type"] = df.apply(
        lambda x: "New" if x["transaction_date"] == x["first_purchase"] else "Returning",
        axis=1
    )

    # demographic clean
    df["gender"] = df["gender"].fillna("Unknown")
    df["city"] = df["city"].fillna("Unknown")

    if "age" not in df.columns:
        if "date_of_birth" in df.columns:
            birth_date = pd.to_datetime(df["date_of_birth"], errors="coerce")
            today = pd.Timestamp.today().normalize()
            df["age"] = (today - birth_date).dt.days / 365.25
        else:
            df["age"] = pd.NA
    else:
        df["age"] = pd.to_numeric(df["age"], errors="coerce")

    df["age_group"] = pd.cut(
        df["age"],
        bins=[0, 25, 35, 50, 100],
        labels=["Gen Z", "Millennial", "Gen X", "Boomer"]
    )

    return df, customer_summary

# ----------------------------
# RFM SEGMENTATION
# ----------------------------
def rfm_analysis(df: pd.DataFrame) -> pd.DataFrame:
    df = df[df["customer_id"].astype(str).str.upper().ne("UNKNOWN_CUSTOMER")].copy()
    analysis_date = df["transaction_date"].max() + pd.Timedelta(days=1)

    rfm = df.groupby("customer_id").agg(
        recency=("transaction_date", lambda x: (analysis_date - x.max()).days),
        frequency=("invoice_id", "nunique"),
        monetary=("revenue", "sum")
    ).reset_index()

    rfm["R_score"] = pd.qcut(
        rfm["recency"].rank(method="first"),
        q=5,
        labels=[5, 4, 3, 2, 1]
    ).astype(int)
    rfm["F_score"] = pd.qcut(
        rfm["frequency"].rank(method="first"),
        q=5,
        labels=[1, 2, 3, 4, 5]
    ).astype(int)
    rfm["M_score"] = pd.qcut(
        rfm["monetary"].rank(method="first"),
        q=5,
        labels=[1, 2, 3, 4, 5]
    ).astype(int)

    rfm["RFM_score"] = rfm["R_score"] + rfm["F_score"] + rfm["M_score"]
    rfm["RFM_code"] = (
        rfm["R_score"].astype(str) + rfm["F_score"].astype(str) + rfm["M_score"].astype(str)
    )

    def assign_rfm_segment(row):
        if row["R_score"] >= 4 and row["F_score"] >= 4 and row["M_score"] >= 4:
            return "Champions"
        if row["R_score"] >= 4 and row["F_score"] >= 3:
            return "Loyal Customers"
        if row["R_score"] >= 4 and row["F_score"] <= 2:
            return "New / Promising"
        if row["R_score"] <= 2 and row["F_score"] >= 4:
            return "At Risk"
        if row["R_score"] <= 2 and row["F_score"] <= 2:
            return "Lost"
        return "Need Attention"

    rfm["RFM_segment"] = rfm.apply(assign_rfm_segment, axis=1)

    segment_summary = rfm.groupby("RFM_segment").agg(
        customers=("customer_id", "nunique"),
        avg_recency=("recency", "mean"),
        avg_frequency=("frequency", "mean"),
        revenue=("monetary", "sum"),
        avg_rfm_score=("RFM_score", "mean")
    ).reset_index().sort_values("revenue", ascending=False)

    print("\n===== RFM SEGMENTATION =====")
    print(segment_summary)

    sns.barplot(data=segment_summary, x="RFM_segment", y="revenue")
    plt.title("Revenue by RFM Segment")
    plt.xticks(rotation=30, ha="right")
    plt.tight_layout()
    plt.show()

    print("\n===== TOP RFM CUSTOMERS =====")
    print(rfm.sort_values("RFM_score", ascending=False).head(10))

    return rfm


# ----------------------------
# COHORT ANALYSIS
# ----------------------------
def cohort_analysis(df: pd.DataFrame) -> pd.DataFrame:
    purchase_df = df[
        (df["revenue"] > 0)
        & df["customer_id"].astype(str).str.upper().ne("UNKNOWN_CUSTOMER")
    ].copy()

    if purchase_df.empty:
        print("\n===== COHORT RETENTION =====")
        print("No positive purchase rows available for cohort analysis.")
        return pd.DataFrame()

    purchase_df["order_month"] = purchase_df["transaction_date"].dt.to_period("M")
    purchase_df["cohort_month"] = purchase_df.groupby("customer_id")["transaction_date"].transform("min").dt.to_period("M")
    purchase_df["cohort_index"] = (
        (purchase_df["order_month"].dt.year - purchase_df["cohort_month"].dt.year) * 12
        + (purchase_df["order_month"].dt.month - purchase_df["cohort_month"].dt.month)
        + 1
    )

    cohort_counts = purchase_df.groupby(["cohort_month", "cohort_index"])["customer_id"].nunique().reset_index()
    cohort_pivot = cohort_counts.pivot(index="cohort_month", columns="cohort_index", values="customer_id")
    cohort_size = cohort_pivot.iloc[:, 0]
    retention = cohort_pivot.divide(cohort_size, axis=0).round(4)

    print("\n===== COHORT RETENTION RATE =====")
    print(retention.fillna(0).head(12))

    plt.figure(figsize=(12, 6))
    sns.heatmap(retention.fillna(0), annot=False, cmap="YlGnBu", fmt=".0%")
    plt.title("Customer Cohort Retention Rate")
    plt.xlabel("Months Since First Purchase")
    plt.ylabel("Cohort Month")
    plt.tight_layout()
    plt.show()

    return retention


# ----------------------------
# CUSTOMER LIFETIME VALUE
# ----------------------------
def clv_analysis(customer_summary: pd.DataFrame) -> pd.DataFrame:
    clv = customer_summary[
        customer_summary["customer_id"].astype(str).str.upper().ne("UNKNOWN_CUSTOMER")
    ].copy()
    analysis_date = clv["last_purchase"].max() + pd.Timedelta(days=1)
    clv["customer_lifespan_days"] = (clv["last_purchase"] - clv["first_purchase"]).dt.days.fillna(0)
    clv["observed_customer_days"] = (analysis_date - clv["first_purchase"]).dt.days.clip(lower=30)
    clv["annualized_clv"] = clv["customer_revenue"] / (clv["observed_customer_days"] / 365.25)

    total_revenue = clv["customer_revenue"].sum()
    total_orders = clv["customer_orders"].sum()
    total_customers = clv["customer_id"].nunique()

    average_order_value = total_revenue / total_orders if total_orders else 0
    purchase_frequency = total_orders / total_customers if total_customers else 0
    historical_clv = total_revenue / total_customers if total_customers else 0
    average_lifespan_days = clv["customer_lifespan_days"].mean()

    clv["historical_clv"] = clv["customer_revenue"]
    clv["clv_tier"] = pd.qcut(
        clv["historical_clv"].rank(method="first"),
        q=4,
        labels=["Low CLV", "Mid CLV", "High CLV", "VIP CLV"]
    )

    clv_summary = clv.groupby("clv_tier").agg(
        customers=("customer_id", "nunique"),
        revenue=("historical_clv", "sum"),
        avg_clv=("historical_clv", "mean"),
        avg_orders=("customer_orders", "mean"),
        avg_aov=("customer_AOV", "mean"),
        avg_lifespan_days=("customer_lifespan_days", "mean"),
        avg_observed_days=("observed_customer_days", "mean"),
        avg_annualized_clv=("annualized_clv", "mean")
    ).reset_index()

    print("\n===== CLV SUMMARY =====")
    print(f"Average Order Value: {average_order_value:,.2f}")
    print(f"Purchase Frequency: {purchase_frequency:,.2f} orders/customer")
    print(f"Historical CLV per Customer: {historical_clv:,.2f}")
    print(f"Average Customer Lifespan: {average_lifespan_days:,.1f} days")
    print(clv_summary)

    sns.barplot(data=clv_summary, x="clv_tier", y="avg_clv")
    plt.title("Average Historical CLV by Tier")
    plt.xticks(rotation=20, ha="right")
    plt.tight_layout()
    plt.show()

    print("\n===== TOP CLV CUSTOMERS =====")
    print(clv.sort_values("historical_clv", ascending=False).head(10))

    return clv


# ----------------------------
# CUSTOMER ANALYSIS
# ----------------------------
def customer_analysis(df: pd.DataFrame):

    df, customer_summary = prepare_customer_data(df)

    # ----------------------------
    # OVERVIEW
    # ----------------------------
    print("\n===== CUSTOMER OVERVIEW =====")
    print("Total Customers:", customer_summary["customer_id"].nunique())
    print("Avg Revenue per Customer:", round(customer_summary["customer_revenue"].mean(), 2))

    # ----------------------------
    # SEGMENTATION
    # ----------------------------
    seg = customer_summary.groupby("customer_segment").agg(
        customers=("customer_id", "nunique"),
        revenue=("customer_revenue", "sum")
    ).reset_index()

    print("\n===== CUSTOMER SEGMENT =====")
    print(seg)

    sns.barplot(data=seg, x="customer_segment", y="revenue")
    plt.title("Revenue by Customer Segment")
    plt.show()

    # ----------------------------
    # NEW VS RETURNING
    # ----------------------------
    nv = df.groupby("customer_type")["revenue"].sum().reset_index()

    print("\n===== NEW VS RETURNING =====")
    print(nv)

    sns.barplot(data=nv, x="customer_type", y="revenue")
    plt.title("Revenue: New vs Returning")
    plt.show()

    # ----------------------------
    # AGE
    # ----------------------------
    age = df.groupby("age_group")["revenue"].sum().reset_index()

    print("\n===== AGE GROUP =====")
    print(age)

    sns.barplot(data=age, x="age_group", y="revenue")
    plt.title("Revenue by Age Group")
    plt.show()

    # ----------------------------
    # CITY
    # ----------------------------
    city = df.groupby("city")["revenue"].sum().sort_values(ascending=False).head(10)

    print("\n===== TOP CITIES =====")
    print(city)

    city.plot(kind="bar")
    plt.title("Top Cities by Revenue")
    plt.show()

    rfm_analysis(df)
    cohort_analysis(df)
    clv_analysis(customer_summary)



# ----------------------------
# PRODUCT DATA PREPARATION
# ----------------------------
def prepare_product_data(df: pd.DataFrame) -> pd.DataFrame:
    if "revenue" not in df.columns:
        df, _ = prepare_sales_data(df)

    df = df.copy()

    conn = sqlite3.connect(DB_PATH)
    product_df = pd.read_sql("SELECT * FROM products_final;", conn)
    conn.close()

    product_df = product_df.rename(columns={
        "description_en": "product_name",
        "color": "product_master_color",
        "size": "available_sizes"
    })

    df["product_id"] = df["product_id"].astype(str)
    product_df["product_id"] = product_df["product_id"].astype(str)
    product_df["production_cost"] = pd.to_numeric(product_df["production_cost"], errors="coerce").fillna(0)

    product_cols = [
        "product_id", "category", "sub_category", "product_name",
        "product_master_color", "available_sizes", "production_cost"
    ]
    df = df.merge(product_df[product_cols], on="product_id", how="left")

    df["product_name"] = df["product_name"].fillna("Unknown Product")
    df["category"] = df["category"].fillna("Unknown")
    df["sub_category"] = df["sub_category"].fillna("Unknown")
    df["product_master_color"] = df["product_master_color"].fillna("Unknown")
    df["available_sizes"] = df["available_sizes"].fillna("Unknown")
    df["production_cost"] = df["production_cost"].fillna(0)

    df["signed_quantity"] = df.apply(
        lambda x: -abs(x["quantity"]) if x["is_return"] else abs(x["quantity"]),
        axis=1
    )
    df["units_sold"] = df["quantity"].where(~df["is_return"], 0)
    df["units_returned"] = df["quantity"].where(df["is_return"], 0)
    df["cost_impact"] = df["production_cost"] * df["signed_quantity"]
    df["gross_profit"] = df["revenue"] - df["cost_impact"]
    df["profit_margin"] = df["gross_profit"] / df["revenue"].where(df["revenue"] != 0)

    return df


# ----------------------------
# PRODUCT ANALYSIS
# ----------------------------
def product_analysis(df: pd.DataFrame) -> pd.DataFrame:
    df = prepare_product_data(df)
    unknown_product_mask = (
        df["product_id"].astype(str).str.upper().eq("UNKNOWN_PRODUCT")
        | df["category"].eq("Unknown")
    )
    unknown_product_revenue = df.loc[unknown_product_mask, "revenue"].sum()
    unknown_product_rows = unknown_product_mask.sum()
    analysis_df = df.loc[~unknown_product_mask].copy()

    product_summary = analysis_df.groupby(["product_id", "product_name", "category", "sub_category"], dropna=False).agg(
        revenue=("revenue", "sum"),
        gross_sales=("gross_sales", "sum"),
        gross_profit=("gross_profit", "sum"),
        cost=("cost_impact", "sum"),
        quantity=("signed_quantity", "sum"),
        units_sold=("units_sold", "sum"),
        units_returned=("units_returned", "sum"),
        orders=("invoice_id", "nunique"),
        avg_unit_price=("unit_price", "mean"),
        avg_discount=("discount", "mean"),
        production_cost=("production_cost", "mean"),
        return_rows=("is_return", "sum")
    ).reset_index()

    product_summary["profit_margin"] = product_summary["gross_profit"] / product_summary["revenue"].where(product_summary["revenue"] != 0)
    product_summary["return_rate"] = product_summary["units_returned"] / (product_summary["units_sold"] + product_summary["units_returned"]).where(
        (product_summary["units_sold"] + product_summary["units_returned"]) != 0
    )
    product_summary = product_summary.sort_values("revenue", ascending=False)

    total_revenue = product_summary["revenue"].sum()
    total_profit = product_summary["gross_profit"].sum()
    total_units = product_summary["units_sold"].sum()
    active_products = product_summary["product_id"].nunique()
    missing_products = df.loc[df["product_name"].eq("Unknown Product"), "product_id"].nunique()

    print("\n===== PRODUCT OVERVIEW =====")
    print(f"Active Known Products Sold: {active_products:,}")
    print(f"Products Missing Master Data: {missing_products:,}")
    print(f"Unknown Product Rows Excluded: {unknown_product_rows:,}")
    print(f"Unknown Product Revenue Excluded: {unknown_product_revenue:,.2f}")
    print(f"Known Product Revenue: {total_revenue:,.2f}")
    print(f"Known Product Gross Profit: {total_profit:,.2f}")
    print(f"Known Product Gross Margin: {(total_profit / total_revenue if total_revenue else 0):.2%}")
    print(f"Known Product Units Sold: {total_units:,.0f}")

    print("\n===== TOP 10 PRODUCTS BY REVENUE =====")
    print(product_summary[["product_id", "product_name", "category", "sub_category", "revenue", "quantity", "gross_profit", "profit_margin"]].head(10))

    print("\n===== TOP 10 PRODUCTS BY PROFIT =====")
    print(product_summary.sort_values("gross_profit", ascending=False)[["product_id", "product_name", "category", "sub_category", "revenue", "gross_profit", "profit_margin"]].head(10))

    print("\n===== BOTTOM 10 PRODUCTS BY PROFIT =====")
    print(product_summary.sort_values("gross_profit")[["product_id", "product_name", "category", "sub_category", "revenue", "gross_profit", "profit_margin", "return_rate"]].head(10))

    category_summary = analysis_df.groupby("category", dropna=False).agg(
        revenue=("revenue", "sum"),
        quantity=("signed_quantity", "sum"),
        units_sold=("units_sold", "sum"),
        gross_profit=("gross_profit", "sum"),
        orders=("invoice_id", "nunique"),
        products=("product_id", "nunique"),
        avg_discount=("discount", "mean"),
        units_returned=("units_returned", "sum")
    ).reset_index().sort_values("revenue", ascending=False)
    category_summary["profit_margin"] = category_summary["gross_profit"] / category_summary["revenue"].where(category_summary["revenue"] != 0)
    category_summary["return_rate"] = category_summary["units_returned"] / (category_summary["units_sold"] + category_summary["units_returned"]).where(
        (category_summary["units_sold"] + category_summary["units_returned"]) != 0
    )

    print("\n===== CATEGORY PERFORMANCE =====")
    print(category_summary)

    sns.barplot(data=category_summary, x="category", y="revenue")
    plt.title("Revenue by Category")
    plt.xticks(rotation=30, ha="right")
    plt.tight_layout()
    plt.show()

    sub_category_summary = analysis_df.groupby(["category", "sub_category"], dropna=False).agg(
        revenue=("revenue", "sum"),
        quantity=("signed_quantity", "sum"),
        gross_profit=("gross_profit", "sum"),
        orders=("invoice_id", "nunique"),
        products=("product_id", "nunique")
    ).reset_index().sort_values("revenue", ascending=False)
    sub_category_summary["profit_margin"] = sub_category_summary["gross_profit"] / sub_category_summary["revenue"].where(sub_category_summary["revenue"] != 0)

    print("\n===== TOP 15 SUB-CATEGORIES =====")
    print(sub_category_summary.head(15))

    plt.figure(figsize=(12, 6))
    sns.barplot(data=sub_category_summary.head(15), x="sub_category", y="revenue", hue="category")
    plt.title("Top Sub-Categories by Revenue")
    plt.xticks(rotation=45, ha="right")
    plt.tight_layout()
    plt.show()

    return_summary = product_summary.sort_values("return_rate", ascending=False)
    return_summary = return_summary[return_summary["units_returned"] > 0]

    print("\n===== TOP RETURNED PRODUCTS =====")
    print(return_summary[["product_id", "product_name", "category", "sub_category", "units_sold", "units_returned", "return_rate", "revenue"]].head(10))

    discount_summary = analysis_df.groupby("category", dropna=False).agg(
        avg_discount=("discount", "mean"),
        revenue=("revenue", "sum"),
        gross_profit=("gross_profit", "sum")
    ).reset_index().sort_values("avg_discount", ascending=False)
    discount_summary["profit_margin"] = discount_summary["gross_profit"] / discount_summary["revenue"].where(discount_summary["revenue"] != 0)

    print("\n===== DISCOUNT IMPACT BY CATEGORY =====")
    print(discount_summary)

    color_summary = analysis_df.groupby("color", dropna=False).agg(
        revenue=("revenue", "sum"),
        quantity=("signed_quantity", "sum"),
        gross_profit=("gross_profit", "sum")
    ).reset_index().sort_values("revenue", ascending=False).head(10)

    size_summary = analysis_df.groupby("size", dropna=False).agg(
        revenue=("revenue", "sum"),
        quantity=("signed_quantity", "sum"),
        gross_profit=("gross_profit", "sum")
    ).reset_index().sort_values("revenue", ascending=False)

    print("\n===== TOP COLORS =====")
    print(color_summary)

    print("\n===== SIZE PERFORMANCE =====")
    print(size_summary)

    product_summary = product_summary.sort_values("revenue", ascending=False).reset_index(drop=True)
    product_summary["revenue_share"] = product_summary["revenue"] / product_summary["revenue"].sum()
    product_summary["cumulative_revenue_share"] = product_summary["revenue_share"].cumsum()
    product_summary["ABC_class"] = pd.cut(
        product_summary["cumulative_revenue_share"],
        bins=[0, 0.8, 0.95, 1.0],
        labels=["A", "B", "C"],
        include_lowest=True
    )

    abc_summary = product_summary.groupby("ABC_class").agg(
        products=("product_id", "nunique"),
        revenue=("revenue", "sum"),
        gross_profit=("gross_profit", "sum"),
        avg_margin=("profit_margin", "mean")
    ).reset_index()
    abc_summary["revenue_share"] = abc_summary["revenue"] / product_summary["revenue"].sum()

    print("\n===== ABC ANALYSIS =====")
    print(abc_summary)

    monthly_category = analysis_df.groupby(["month", "category"], as_index=False)["revenue"].sum()
    top_categories = category_summary.head(5)["category"].tolist()
    monthly_top_category = monthly_category[monthly_category["category"].isin(top_categories)]

    print("\n===== MONTHLY TREND: TOP CATEGORIES =====")
    print(monthly_top_category.tail(20))

    plt.figure(figsize=(12, 6))
    sns.lineplot(data=monthly_top_category, x="month", y="revenue", hue="category", marker="o")
    plt.title("Monthly Revenue Trend by Top Categories")
    plt.xticks(rotation=45, ha="right")
    plt.tight_layout()
    plt.show()

    return product_summary


# ----------------------------
# STORE DATA PREPARATION
# ----------------------------
def prepare_store_data(df: pd.DataFrame) -> pd.DataFrame:
    df = prepare_product_data(df)

    conn = sqlite3.connect(DB_PATH)
    store_df = pd.read_sql("SELECT * FROM stores_final;", conn)
    conn.close()

    df["store_id"] = df["store_id"].astype(str)
    store_df["store_id"] = store_df["store_id"].astype(str)
    store_df["number_of_employees"] = pd.to_numeric(store_df["number_of_employees"], errors="coerce")

    df = df.merge(store_df, on="store_id", how="left")

    df["store_name"] = df["store_name"].fillna("Unknown Store")
    df["country"] = df["country"].fillna("Unknown")
    df["city"] = df["city"].fillna("Unknown")
    df["zip_code"] = df["zip_code"].fillna("Unknown")
    df["number_of_employees"] = df["number_of_employees"].fillna(0)

    return df


# ----------------------------
# STORE ANALYSIS
# ----------------------------
def store_analysis(df: pd.DataFrame) -> pd.DataFrame:
    df = prepare_store_data(df)
    unknown_store_mask = df["store_name"].eq("Unknown Store") | df["country"].eq("Unknown")
    unknown_store_revenue = df.loc[unknown_store_mask, "revenue"].sum()
    unknown_store_rows = unknown_store_mask.sum()
    analysis_df = df.loc[~unknown_store_mask].copy()

    store_summary = analysis_df.groupby(
        ["store_id", "store_name", "country", "city", "number_of_employees"],
        dropna=False
    ).agg(
        revenue=("revenue", "sum"),
        gross_profit=("gross_profit", "sum"),
        quantity=("signed_quantity", "sum"),
        units_sold=("units_sold", "sum"),
        units_returned=("units_returned", "sum"),
        orders=("invoice_id", "nunique"),
        customers=("customer_id", "nunique"),
        products=("product_id", "nunique"),
        avg_discount=("discount", "mean"),
        return_rows=("is_return", "sum")
    ).reset_index()

    store_summary["AOV"] = store_summary["revenue"] / store_summary["orders"].where(store_summary["orders"] != 0)
    store_summary["profit_margin"] = store_summary["gross_profit"] / store_summary["revenue"].where(store_summary["revenue"] != 0)
    store_summary["return_rate"] = store_summary["units_returned"] / (store_summary["units_sold"] + store_summary["units_returned"]).where(
        (store_summary["units_sold"] + store_summary["units_returned"]) != 0
    )
    store_summary["revenue_per_employee"] = store_summary["revenue"] / store_summary["number_of_employees"].where(store_summary["number_of_employees"] != 0)
    store_summary["profit_per_employee"] = store_summary["gross_profit"] / store_summary["number_of_employees"].where(store_summary["number_of_employees"] != 0)
    store_summary["orders_per_employee"] = store_summary["orders"] / store_summary["number_of_employees"].where(store_summary["number_of_employees"] != 0)
    store_summary = store_summary.sort_values("revenue", ascending=False)

    total_revenue = store_summary["revenue"].sum()
    total_profit = store_summary["gross_profit"].sum()
    total_orders = store_summary["orders"].sum()
    active_stores = store_summary["store_id"].nunique()

    print("\n===== STORE OVERVIEW =====")
    print(f"Active Known Stores: {active_stores:,}")
    print(f"Unknown Store Rows Excluded: {unknown_store_rows:,}")
    print(f"Unknown Store Revenue Excluded: {unknown_store_revenue:,.2f}")
    print(f"Known Store Revenue: {total_revenue:,.2f}")
    print(f"Known Store Gross Profit: {total_profit:,.2f}")
    print(f"Known Store Gross Margin: {(total_profit / total_revenue if total_revenue else 0):.2%}")
    print(f"Known Store Orders: {total_orders:,}")
    print(f"Average Revenue per Store: {(total_revenue / active_stores if active_stores else 0):,.2f}")

    print("\n===== TOP 10 STORES BY REVENUE =====")
    print(store_summary[["store_id", "store_name", "country", "city", "revenue", "orders", "gross_profit", "profit_margin", "AOV"]].head(10))

    print("\n===== BOTTOM 10 STORES BY REVENUE =====")
    print(store_summary.sort_values("revenue")[["store_id", "store_name", "country", "city", "revenue", "orders", "gross_profit", "profit_margin", "AOV"]].head(10))

    print("\n===== TOP 10 STORES BY REVENUE PER EMPLOYEE =====")
    print(store_summary.sort_values("revenue_per_employee", ascending=False)[[
        "store_id", "store_name", "country", "city", "number_of_employees",
        "revenue", "revenue_per_employee", "profit_per_employee", "orders_per_employee"
    ]].head(10))

    country_summary = analysis_df.groupby("country", dropna=False).agg(
        stores=("store_id", "nunique"),
        revenue=("revenue", "sum"),
        gross_profit=("gross_profit", "sum"),
        orders=("invoice_id", "nunique"),
        customers=("customer_id", "nunique"),
        units_sold=("units_sold", "sum"),
        units_returned=("units_returned", "sum"),
        avg_discount=("discount", "mean")
    ).reset_index().sort_values("revenue", ascending=False)
    country_summary["AOV"] = country_summary["revenue"] / country_summary["orders"].where(country_summary["orders"] != 0)
    country_summary["profit_margin"] = country_summary["gross_profit"] / country_summary["revenue"].where(country_summary["revenue"] != 0)
    country_summary["return_rate"] = country_summary["units_returned"] / (country_summary["units_sold"] + country_summary["units_returned"]).where(
        (country_summary["units_sold"] + country_summary["units_returned"]) != 0
    )

    print("\n===== COUNTRY PERFORMANCE =====")
    print(country_summary)

    sns.barplot(data=country_summary, x="country", y="revenue")
    plt.title("Revenue by Country")
    plt.xticks(rotation=30, ha="right")
    plt.tight_layout()
    plt.show()

    city_summary = analysis_df.groupby(["country", "city"], dropna=False).agg(
        stores=("store_id", "nunique"),
        revenue=("revenue", "sum"),
        gross_profit=("gross_profit", "sum"),
        orders=("invoice_id", "nunique"),
        customers=("customer_id", "nunique"),
        units_sold=("units_sold", "sum"),
        units_returned=("units_returned", "sum")
    ).reset_index().sort_values("revenue", ascending=False)
    city_summary["profit_margin"] = city_summary["gross_profit"] / city_summary["revenue"].where(city_summary["revenue"] != 0)
    city_summary["return_rate"] = city_summary["units_returned"] / (city_summary["units_sold"] + city_summary["units_returned"]).where(
        (city_summary["units_sold"] + city_summary["units_returned"]) != 0
    )

    print("\n===== TOP 15 CITIES BY REVENUE =====")
    print(city_summary.head(15))

    plt.figure(figsize=(12, 6))
    sns.barplot(data=city_summary.head(15), x="city", y="revenue", hue="country")
    plt.title("Top Cities by Store Revenue")
    plt.xticks(rotation=45, ha="right")
    plt.tight_layout()
    plt.show()

    return_summary = store_summary.sort_values("return_rate", ascending=False)

    print("\n===== STORES WITH HIGHEST RETURN RATE =====")
    print(return_summary[["store_id", "store_name", "country", "city", "units_sold", "units_returned", "return_rate", "revenue"]].head(10))

    discount_summary = store_summary.sort_values("avg_discount", ascending=False)

    print("\n===== STORES WITH HIGHEST AVG DISCOUNT =====")
    print(discount_summary[["store_id", "store_name", "country", "city", "avg_discount", "revenue", "gross_profit", "profit_margin"]].head(10))

    store_category = analysis_df.groupby(["store_id", "store_name", "country", "city", "category"], as_index=False).agg(
        revenue=("revenue", "sum"),
        gross_profit=("gross_profit", "sum"),
        quantity=("signed_quantity", "sum")
    )
    store_category["category_rank"] = store_category.groupby("store_id")["revenue"].rank(method="first", ascending=False)
    top_category_by_store = store_category[store_category["category_rank"].eq(1)].sort_values("revenue", ascending=False)

    print("\n===== TOP CATEGORY BY STORE =====")
    print(top_category_by_store[["store_id", "store_name", "country", "city", "category", "revenue", "gross_profit", "quantity"]].head(20))

    category_mix = analysis_df.groupby(["country", "category"], as_index=False).agg(
        revenue=("revenue", "sum"),
        gross_profit=("gross_profit", "sum"),
        quantity=("signed_quantity", "sum")
    ).sort_values("revenue", ascending=False)

    print("\n===== COUNTRY CATEGORY MIX =====")
    print(category_mix)

    monthly_store = analysis_df.groupby(["month", "store_name"], as_index=False)["revenue"].sum()
    top_stores = store_summary.head(5)["store_name"].tolist()
    monthly_top_store = monthly_store[monthly_store["store_name"].isin(top_stores)]

    print("\n===== MONTHLY TREND: TOP STORES =====")
    print(monthly_top_store.tail(25))

    plt.figure(figsize=(12, 6))
    sns.lineplot(data=monthly_top_store, x="month", y="revenue", hue="store_name", marker="o")
    plt.title("Monthly Revenue Trend by Top Stores")
    plt.xticks(rotation=45, ha="right")
    plt.tight_layout()
    plt.show()

    employee_summary = store_summary.copy()
    employee_summary["employee_band"] = pd.cut(
        employee_summary["number_of_employees"],
        bins=[0, 5, 8, 10, 20],
        labels=["1-5", "6-8", "9-10", "11+"],
        include_lowest=True
    )
    employee_band_summary = employee_summary.groupby("employee_band", dropna=False).agg(
        stores=("store_id", "nunique"),
        revenue=("revenue", "sum"),
        avg_revenue_per_employee=("revenue_per_employee", "mean"),
        avg_profit_per_employee=("profit_per_employee", "mean")
    ).reset_index()

    print("\n===== STORE PRODUCTIVITY BY EMPLOYEE BAND =====")
    print(employee_band_summary)

    return store_summary


# ----------------------------
# DISCOUNT DATA PREPARATION
# ----------------------------
def prepare_discount_data(df: pd.DataFrame) -> pd.DataFrame:
    df = prepare_product_data(df)

    conn = sqlite3.connect(DB_PATH)
    discount_df = pd.read_sql("SELECT * FROM discounts;", conn)
    conn.close()

    discount_df["start"] = pd.to_datetime(discount_df["start"], errors="coerce")
    discount_df["end"] = pd.to_datetime(discount_df["end"], errors="coerce")
    discount_df["discount"] = pd.to_numeric(discount_df["discount"], errors="coerce")
    discount_df = discount_df.dropna(subset=["start", "end", "discount", "category", "sub_category"])

    df["campaign_description"] = "No Campaign"
    df["campaign_discount"] = 0.0
    df["is_campaign_period"] = False

    for row in discount_df.itertuples(index=False):
        mask = (
            df["transaction_date"].between(row.start, row.end, inclusive="both")
            & df["category"].eq(row.category)
            & df["sub_category"].eq(row.sub_category)
        )
        df.loc[mask, "campaign_description"] = row.description
        df.loc[mask, "campaign_discount"] = row.discount
        df.loc[mask, "is_campaign_period"] = True

    df["has_discount"] = df["discount"] > 0
    df["discount_gap"] = df["discount"] - df["campaign_discount"]
    df["discount_status"] = "No Discount"
    df.loc[df["is_campaign_period"] & df["has_discount"], "discount_status"] = "Campaign Discount"
    df.loc[df["is_campaign_period"] & ~df["has_discount"], "discount_status"] = "Campaign Listed / No Discount Applied"
    df.loc[~df["is_campaign_period"] & df["has_discount"], "discount_status"] = "Non-Campaign Discount"

    return df


# ----------------------------
# DISCOUNT ANALYSIS
# ----------------------------
def discount_analysis(df: pd.DataFrame) -> pd.DataFrame:
    df = prepare_discount_data(df)

    total_revenue = df["revenue"].sum()
    total_profit = df["gross_profit"].sum()
    discounted_revenue = df.loc[df["has_discount"], "revenue"].sum()
    no_discount_revenue = df.loc[~df["has_discount"], "revenue"].sum()
    campaign_revenue = df.loc[df["is_campaign_period"], "revenue"].sum()
    non_campaign_revenue = df.loc[~df["is_campaign_period"], "revenue"].sum()

    print("\n===== DISCOUNT OVERVIEW =====")
    print(f"Total Revenue: {total_revenue:,.2f}")
    print(f"Total Gross Profit: {total_profit:,.2f}")
    print(f"Discounted Revenue: {discounted_revenue:,.2f}")
    print(f"Non-Discounted Revenue: {no_discount_revenue:,.2f}")
    print(f"Campaign Period Revenue: {campaign_revenue:,.2f}")
    print(f"Non-Campaign Period Revenue: {non_campaign_revenue:,.2f}")
    print(f"Rows in Campaign Period: {df['is_campaign_period'].sum():,}")
    print(f"Rows with Actual Discount: {df['has_discount'].sum():,}")

    status_summary = df.groupby("discount_status").agg(
        rows=("invoice_id", "count"),
        orders=("invoice_id", "nunique"),
        revenue=("revenue", "sum"),
        gross_profit=("gross_profit", "sum"),
        quantity=("signed_quantity", "sum"),
        avg_discount=("discount", "mean"),
        avg_campaign_discount=("campaign_discount", "mean"),
        return_rows=("is_return", "sum")
    ).reset_index().sort_values("revenue", ascending=False)
    status_summary["profit_margin"] = status_summary["gross_profit"] / status_summary["revenue"].where(status_summary["revenue"] != 0)
    status_summary["return_row_rate"] = status_summary["return_rows"] / status_summary["rows"].where(status_summary["rows"] != 0)

    print("\n===== DISCOUNT STATUS PERFORMANCE =====")
    print(status_summary)

    sns.barplot(data=status_summary, x="discount_status", y="revenue")
    plt.title("Revenue by Discount Status")
    plt.xticks(rotation=30, ha="right")
    plt.tight_layout()
    plt.show()

    discount_group_summary = df.groupby("discount_group", dropna=False).agg(
        rows=("invoice_id", "count"),
        orders=("invoice_id", "nunique"),
        revenue=("revenue", "sum"),
        gross_profit=("gross_profit", "sum"),
        quantity=("signed_quantity", "sum"),
        avg_discount=("discount", "mean"),
        return_rows=("is_return", "sum")
    ).reset_index()
    discount_group_summary["profit_margin"] = discount_group_summary["gross_profit"] / discount_group_summary["revenue"].where(discount_group_summary["revenue"] != 0)
    discount_group_summary["return_row_rate"] = discount_group_summary["return_rows"] / discount_group_summary["rows"].where(discount_group_summary["rows"] != 0)

    print("\n===== DISCOUNT GROUP PERFORMANCE =====")
    print(discount_group_summary)

    campaign_summary = df[df["is_campaign_period"]].groupby("campaign_description").agg(
        rows=("invoice_id", "count"),
        orders=("invoice_id", "nunique"),
        revenue=("revenue", "sum"),
        gross_profit=("gross_profit", "sum"),
        quantity=("signed_quantity", "sum"),
        avg_actual_discount=("discount", "mean"),
        campaign_discount=("campaign_discount", "mean"),
        return_rows=("is_return", "sum")
    ).reset_index().sort_values("revenue", ascending=False)
    campaign_summary["profit_margin"] = campaign_summary["gross_profit"] / campaign_summary["revenue"].where(campaign_summary["revenue"] != 0)
    campaign_summary["discount_gap"] = campaign_summary["avg_actual_discount"] - campaign_summary["campaign_discount"]
    campaign_summary["return_row_rate"] = campaign_summary["return_rows"] / campaign_summary["rows"].where(campaign_summary["rows"] != 0)

    print("\n===== CAMPAIGN PERFORMANCE =====")
    print(campaign_summary)

    if not campaign_summary.empty:
        plt.figure(figsize=(12, 6))
        sns.barplot(data=campaign_summary, x="campaign_description", y="revenue")
        plt.title("Revenue by Discount Campaign")
        plt.xticks(rotation=45, ha="right")
        plt.tight_layout()
        plt.show()

    category_discount = df.groupby(["category", "discount_status"], dropna=False).agg(
        revenue=("revenue", "sum"),
        gross_profit=("gross_profit", "sum"),
        quantity=("signed_quantity", "sum"),
        orders=("invoice_id", "nunique"),
        avg_discount=("discount", "mean")
    ).reset_index().sort_values("revenue", ascending=False)
    category_discount["profit_margin"] = category_discount["gross_profit"] / category_discount["revenue"].where(category_discount["revenue"] != 0)

    print("\n===== CATEGORY X DISCOUNT STATUS =====")
    print(category_discount)

    campaign_category = df[df["is_campaign_period"]].groupby(["campaign_description", "category", "sub_category"], dropna=False).agg(
        revenue=("revenue", "sum"),
        gross_profit=("gross_profit", "sum"),
        quantity=("signed_quantity", "sum"),
        orders=("invoice_id", "nunique"),
        avg_actual_discount=("discount", "mean"),
        campaign_discount=("campaign_discount", "mean")
    ).reset_index().sort_values("revenue", ascending=False)
    campaign_category["profit_margin"] = campaign_category["gross_profit"] / campaign_category["revenue"].where(campaign_category["revenue"] != 0)
    campaign_category["discount_gap"] = campaign_category["avg_actual_discount"] - campaign_category["campaign_discount"]

    print("\n===== TOP CAMPAIGN CATEGORY/SUB-CATEGORY RESULTS =====")
    print(campaign_category.head(20))

    monthly_discount = df.groupby(["month", "discount_status"], as_index=False).agg(
        revenue=("revenue", "sum"),
        gross_profit=("gross_profit", "sum"),
        orders=("invoice_id", "nunique")
    )

    print("\n===== MONTHLY DISCOUNT TREND =====")
    print(monthly_discount.tail(30))

    plt.figure(figsize=(12, 6))
    sns.lineplot(data=monthly_discount, x="month", y="revenue", hue="discount_status", marker="o")
    plt.title("Monthly Revenue by Discount Status")
    plt.xticks(rotation=45, ha="right")
    plt.tight_layout()
    plt.show()

    discount_correlation = df[["discount", "campaign_discount", "revenue", "gross_profit", "quantity"]].corr()

    print("\n===== DISCOUNT CORRELATION =====")
    print(discount_correlation)

    high_discount_low_margin = df[df["has_discount"]].groupby(
        ["product_id", "product_name", "category", "sub_category"],
        dropna=False
    ).agg(
        revenue=("revenue", "sum"),
        gross_profit=("gross_profit", "sum"),
        quantity=("signed_quantity", "sum"),
        avg_discount=("discount", "mean"),
        orders=("invoice_id", "nunique")
    ).reset_index()
    high_discount_low_margin["profit_margin"] = high_discount_low_margin["gross_profit"] / high_discount_low_margin["revenue"].where(high_discount_low_margin["revenue"] != 0)
    high_discount_low_margin = high_discount_low_margin[
        (high_discount_low_margin["avg_discount"] >= 0.3)
        & (high_discount_low_margin["profit_margin"] < 0.4)
    ].sort_values(["avg_discount", "profit_margin"], ascending=[False, True])

    print("\n===== HIGH DISCOUNT / LOW MARGIN PRODUCTS =====")
    print(high_discount_low_margin.head(20))

    return status_summary

def main():
    df = load_data(DB_PATH, TABLE_NAME)

    df = sales_analysis(df)
    product_analysis(df)
    store_analysis(df)
    discount_analysis(df)
    customer_analysis(df)

if __name__ == "__main__":
    main()