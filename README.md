# Insight Flow – Retail Analytics & Decision Support System

Repository: RetailAnalytics-BusinessInsights

## Project Overview
This project transforms high-volume and inconsistent retail transaction data into reliable business insights through an end-to-end analytics workflow using SQL, Python, SQLite, and Tableau.

The analysis focuses on identifying key revenue drivers across sales, customer behavior, product performance, store operations, basket size, and discount effectiveness to support data-driven decision-making.

## Dataset Overview
- 1.06M transaction records before cleaning
- 196K customers
- 17K products
- 3 stores
- 624K orders


## Business Objective
The objective of this project is to identify revenue drivers and performance improvement opportunities across multiple retail dimensions, including pricing, customers, products, stores, and discounts.

## Key Challenges
The raw dataset contained several data quality issues that could affect analytical reliability:

- Missing and inconsistently formatted values
- Duplicate transaction records
- Misaligned identifiers across tables
- Invalid numeric values
- Revenue inconsistencies caused by duplicated and dirty records

## Workflow
1. Exploratory Data Analysis with SQL
2. Data Cleaning and Validation
3. Relational Data Modeling in SQLite
4. Feature Engineering with Python
5. Sales, Customer, Product, Store, and Discount Analysis
6. Tableau Dashboard Development
7. Business Insight and Recommendation

## Tools & Technologies
- SQL / SQLite
- Python: pandas, matplotlib, seaborn
- Tableau
- Data Cleaning
- Exploratory Data Analysis
- RFM Segmentation
- CLV Analysis
- Business Dashboard Design

## Data Cleaning Summary
| Metric | Before | After |
|---|---:|---:|
| Total Rows | 1.06M | 0.90M |
| Missing Values in Core Fields | ~8–9% | ~0% |
| Duplicate Records | ~10K+ removed | ~0 exact duplicates |
| Total Revenue | 42.67M | 39.50M |

## Key Analysis Areas
### Sales Analysis
- Monthly and quarterly revenue trends
- Average order value
- Revenue driver correlation
- Weekday vs weekend performance

### Customer Analysis
- Customer segmentation
- RFM analysis
- Cohort retention analysis
- Customer lifetime value analysis

### Product Analysis
- Product and category performance
- Gross profit and margin analysis
- Return rate analysis
- ABC product classification

### Store Analysis
- Store revenue and profitability
- Revenue per employee
- Store-level return and discount analysis
- Country and city performance

### Discount Analysis
- Campaign and non-campaign discount performance
- Discount impact on revenue and gross profit
- High-discount and low-margin product identification

## Key Insights
- Net revenue after cleaning reached 39.51M with 624,990 total orders and an AOV of 53.38.
- Revenue showed high volatility, with a peak in December 2023, suggesting reliance on seasonal demand.
- Weekend sales, especially Sunday, generated stronger revenue than most weekdays.
- High-value “Champion” customers contributed strongly to revenue, creating potential dependency risk.
- Small basket sizes dominated transactions, indicating cross-selling and bundle promotion opportunities.
- Feminine and Masculine categories drove most revenue, while Children products contributed significantly less.
- Store New York and Store Los Angeles outperformed Store Chicago in total revenue and productivity.
- Discount strategies required optimization, as no-discount sales contributed the largest revenue share while campaign and non-campaign discounts showed different profitability patterns.

## Business Recommendations
- Prioritize retention strategies for high-value customers.
- Introduce bundle promotions to increase basket size and average order value.
- Optimize discount strategies to protect margins.
- Invest in underperforming product categories to diversify revenue streams.
- Use dashboards as decision-support tools for ongoing performance monitoring.

## Interactive Dashboard
The final dashboard was published on Tableau Public to allow users to explore revenue, customer, product, store, and discount performance interactively.

[View Interactive Tableau Dashboard](https://public.tableau.com/app/profile/phisitphon.jantharakittikun/viz/BusinessPerformanceDashboardRetailCaseStudy/HOME)

## Dashboard Pages
The Tableau dashboard consists of five interactive pages designed to support different business decisions:

- **Sales Dashboard**: Tracks net revenue, total orders, AOV, gross profit, margin, revenue trend, weekday performance, price segment, and basket size.
- **Customer Dashboard**: Analyzes total customers, new customers, repeat rate, CLV, geographic distribution, age groups, and RFM-based customer segmentation.
- **Product Dashboard**: Evaluates product performance, units sold, average margin, loss-making products, profitable products, return rate, revenue contribution, and ABC product mix.
- **Store Dashboard**: Compares store revenue, average revenue per store, best-performing store, employee productivity, peak demand by hour, and store performance matrix.
- **Discount Dashboard**: Assesses discount share, best campaign, effective rate, campaign profit, revenue by discount status, discount trends, ROI, payback, and campaign performance matrix.

## Dashboard Preview

### Sales Dashboard
![Sales Dashboard](images/sales_dashboard.png)

### Customer Dashboard
![Customer Dashboard](images/customer_dashboard.png)

### Product Dashboard
![Product Dashboard](images/product_dashboard.png)

### Store Dashboard
![Store Dashboard](images/store_dashboard.png)

### Discount Dashboard
![Discount Dashboard](images/discount_dashboard.png)

## Project Structure

```text
RetailAnalytics-BusinessInsights/
│
├── README.md
├── requirements.txt
├── .gitignore
│
├── sql/
│   ├── 01_eda_before_cleaning.sql
│   └── 02_data_cleaning.sql
│
├── src/
│   └── retail_analysis.py
│
└── images/
    ├── sales_dashboard.png
    ├── customer_dashboard.png
    ├── product_dashboard.png
    ├── store_dashboard.png
    └── discount_dashboard.png
```


## How to Run

This repository contains the SQL scripts, Python analysis workflow, dashboard screenshots, and project documentation.

The full database is not included due to file size and data privacy considerations.

To run the Python analysis locally, prepare a SQLite database with the required tables and update the database path in `src/retail_analysis.py`.

```bash
pip install -r requirements.txt
python src/retail_analysis.py
```

## Note
The full dataset and SQLite database are not included in this repository due to file size and data privacy considerations. Dashboard screenshots and documentation are provided for portfolio demonstration purposes.
