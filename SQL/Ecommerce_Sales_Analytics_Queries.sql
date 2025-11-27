-- File: Ecommerce_Sales_Analytics_Queries.sql
-- Purpose: Common SQL queries for Ecommerce Sales Analytics (use in your project / notebook)
-- Instructions: Replace table & column names in the "SCHEMA NOTE" block below with your real names

/*******************************
 SCHEMA NOTE (example names)
 - sales (fact table)
    - order_id
    - order_date
    - customer_id
    - product_id
    - quantity
    - unit_price
    - discount_amount
    - tax_amount
    - shipping_amount
    - total_amount   -- final sale amount after discount, etc.
    - profit_amount  -- profit on the line (if available) or calculate as total - cost
    - order_status   -- e.g., 'Completed','Cancelled','Returned'
    - channel        -- 'Website','App','Marketplace'
    - payment_method
    - city
    - state
 - products (dimension)
    - product_id
    - product_name
    - category
    - sub_category
    - cost_price
 - customers (dimension)
    - customer_id
    - customer_name
    - customer_segment
    - signup_date
 - date_dim (optional helpful dimension)
    - date
    - year
    - month
    - month_name
    - quarter
********************************/

-- ===========================================================================
-- 0) Helpful: Standardized CTE for cleaned sales rows (adjust column names)
-- ===========================================================================
WITH cleaned_sales AS (
  SELECT
    order_id,
    CAST(order_date AS DATE) AS order_date,
    customer_id,
    product_id,
    CAST(quantity AS INT) AS quantity,
    CAST(unit_price AS NUMERIC) AS unit_price,
    COALESCE(CAST(discount_amount AS NUMERIC),0) AS discount_amount,
    COALESCE(CAST(tax_amount AS NUMERIC),0) AS tax_amount,
    COALESCE(CAST(shipping_amount AS NUMERIC),0) AS shipping_amount,
    COALESCE(CAST(total_amount AS NUMERIC), (quantity * unit_price) - COALESCE(discount_amount,0) + COALESCE(tax_amount,0) + COALESCE(shipping_amount,0)) AS total_amount,
    COALESCE(CAST(profit_amount AS NUMERIC), NULL) AS profit_amount,
    order_status,
    channel,
    payment_method,
    city,
    state
  FROM sales
)

-- ===========================================================================
-- 1) Overall KPIs: Total Sales, Total Orders, Total Profit, Profit Margin
-- ===========================================================================
SELECT
  COUNT(DISTINCT order_id) AS total_orders,
  SUM(total_amount) AS total_sales,
  SUM(profit_amount) AS total_profit,
  CASE WHEN SUM(total_amount) = 0 THEN 0
       ELSE ROUND(100.0 * SUM(profit_amount) / NULLIF(SUM(total_amount),0),2)
  END AS profit_margin_pct
FROM cleaned_sales
WHERE order_status = 'Completed';

-- ===========================================================================
-- 2) Sales by Year / Month (time series)
-- ===========================================================================
SELECT
  EXTRACT(YEAR FROM order_date) AS year,
  EXTRACT(MONTH FROM order_date) AS month,
  SUM(total_amount) AS sales,
  SUM(COALESCE(profit_amount,0)) AS profit
FROM cleaned_sales
WHERE order_status = 'Completed'
GROUP BY 1,2
ORDER BY 1,2;

-- ===========================================================================
-- 3) Sales Trend (Year-Month string)
-- ===========================================================================
SELECT
  TO_CHAR(order_date,'YYYY-MM') AS year_month,
  SUM(total_amount) AS total_sales,
  SUM(COALESCE(profit_amount,0)) AS total_profit
FROM cleaned_sales
WHERE order_status = 'Completed'
GROUP BY 1
ORDER BY 1;

-- ===========================================================================
-- 4) Sales by Channel (Website / App / Marketplace)
-- ===========================================================================
SELECT
  channel,
  COUNT(DISTINCT order_id) AS orders,
  SUM(total_amount) AS sales,
  ROUND(100.0 * SUM(total_amount) / NULLIF((SELECT SUM(total_amount) FROM cleaned_sales WHERE order_status='Completed'),0),2) AS pct_of_total_sales
FROM cleaned_sales
WHERE order_status = 'Completed'
GROUP BY 1
ORDER BY sales DESC;

-- ===========================================================================
-- 5) Top Products by Sales and Profit
-- ===========================================================================
SELECT
  p.product_id,
  p.product_name,
  p.category,
  SUM(s.total_amount) AS total_sales,
  SUM(COALESCE(s.profit_amount,0)) AS total_profit,
  SUM(s.quantity) AS total_units_sold
FROM cleaned_sales s
LEFT JOIN products p ON s.product_id = p.product_id
WHERE s.order_status = 'Completed'
GROUP BY p.product_id, p.product_name, p.category
ORDER BY total_sales DESC
LIMIT 20;

-- ===========================================================================
-- 6) Category Sales & Profit Breakdown
-- ===========================================================================
SELECT
  p.category,
  SUM(s.total_amount) AS sales,
  SUM(COALESCE(s.profit_amount,0)) AS profit,
  COUNT(DISTINCT s.order_id) AS orders
FROM cleaned_sales s
LEFT JOIN products p ON s.product_id = p.product_id
WHERE s.order_status = 'Completed'
GROUP BY p.category
ORDER BY sales DESC;

-- ===========================================================================
-- 7) Sales by Region / State / City
-- ===========================================================================
SELECT
  state,
  city,
  SUM(total_amount) AS sales,
  COUNT(DISTINCT order_id) AS orders
FROM cleaned_sales
WHERE order_status = 'Completed'
GROUP BY state, city
ORDER BY sales DESC
LIMIT 200;

-- ===========================================================================
-- 8) Cancellation / Return Rate
-- ===========================================================================
SELECT
  SUM(CASE WHEN order_status = 'Cancelled' THEN 1 ELSE 0 END) AS cancelled_orders,
  SUM(CASE WHEN order_status = 'Returned' THEN 1 ELSE 0 END) AS returned_orders,
  COUNT(DISTINCT order_id) AS total_orders_all,
  ROUND(100.0 * SUM(CASE WHEN order_status = 'Cancelled' THEN 1 ELSE 0 END) / NULLIF(COUNT(DISTINCT order_id),0),2) AS cancel_rate_pct,
  ROUND(100.0 * SUM(CASE WHEN order_status = 'Returned' THEN 1 ELSE 0 END) / NULLIF(COUNT(DISTINCT order_id),0),2) AS return_rate_pct
FROM cleaned_sales;

-- ===========================================================================
-- 9) Average Order Value (AOV) and Orders per Customer
-- ===========================================================================
SELECT
  AVG(order_value) AS avg_order_value,
  AVG(orders_per_customer) AS avg_orders_per_customer
FROM (
  SELECT
    customer_id,
    COUNT(DISTINCT order_id) AS orders_per_customer,
    SUM(total_amount) AS total_customer_spend,
    SUM(total_amount) / NULLIF(COUNT(DISTINCT order_id),0) AS order_value
  FROM cleaned_sales
  WHERE order_status = 'Completed'
  GROUP BY customer_id
) t;

-- ===========================================================================
-- 10) Repeat Customers & Repeat Rate
-- ===========================================================================
SELECT
  COUNT(*) FILTER (WHERE orders_count = 1) AS single_order_customers,
  COUNT(*) FILTER (WHERE orders_count > 1) AS repeat_customers,
  ROUND(100.0 * COUNT(*) FILTER (WHERE orders_count > 1) / NULLIF(COUNT(*),0),2) AS repeat_rate_pct
FROM (
  SELECT customer_id, COUNT(DISTINCT order_id) AS orders_count
  FROM cleaned_sales
  WHERE order_status = 'Completed'
  GROUP BY customer_id
) q;

-- ===========================================================================
-- 11) Cohort Analysis (monthly acquisition cohorts, retention by month)
-- ===========================================================================
WITH first_order AS (
  SELECT
    customer_id,
    MIN(order_date) AS first_order_date
  FROM cleaned_sales
  WHERE order_status = 'Completed'
  GROUP BY customer_id
),
cohorts AS (
  SELECT
    s.customer_id,
    DATE_TRUNC('month', f.first_order_date) AS cohort_month,
    DATE_TRUNC('month', s.order_date) AS order_month
  FROM cleaned_sales s
  JOIN first_order f ON s.customer_id = f.customer_id
  WHERE s.order_status = 'Completed'
)
SELECT
  cohort_month,
  order_month,
  COUNT(DISTINCT customer_id) AS customers_active
FROM cohorts
GROUP BY cohort_month, order_month
ORDER BY cohort_month, order_month;

-- ===========================================================================
-- 12) RFM (Recency, Frequency, Monetary) Buckets (example)
-- ===========================================================================
WITH last_order AS (
  SELECT customer_id, MAX(order_date) AS last_order_date, COUNT(DISTINCT order_id) AS frequency, SUM(total_amount) AS monetary
  FROM cleaned_sales
  WHERE order_status = 'Completed'
  GROUP BY customer_id
),
rfm AS (
  SELECT
    customer_id,
    DATE_PART('day', CURRENT_DATE - last_order_date) AS recency_days,
    frequency,
    monetary,
    NTILE(5) OVER (ORDER BY DATE_PART('day', CURRENT_DATE - last_order_date)) AS recency_rank,
    NTILE(5) OVER (ORDER BY frequency DESC) AS frequency_rank,
    NTILE(5) OVER (ORDER BY monetary DESC) AS monetary_rank
  FROM last_order
)
SELECT * FROM rfm
ORDER BY monetary DESC
LIMIT 200;

-- ===========================================================================
-- 13) Customer Lifetime Value (simple approximation)
-- ===========================================================================
WITH cust AS (
  SELECT
    customer_id,
    COUNT(DISTINCT order_id) AS orders,
    SUM(total_amount) AS lifetime_value,
    AVG(total_amount) AS avg_order_value,
    MIN(order_date) AS first_order,
    MAX(order_date) AS last_order
  FROM cleaned_sales
  WHERE order_status = 'Completed'
  GROUP BY customer_id
)
SELECT
  customer_id,
  orders,
  lifetime_value,
  avg_order_value,
  DATE_PART('day', CURRENT_DATE - first_order) AS customer_age_days
FROM cust
ORDER BY lifetime_value DESC
LIMIT 200;

-- ===========================================================================
-- 14) Month-over-Month (MoM) and Year-over-Year (YoY) growth for sales
-- ===========================================================================
WITH monthly AS (
  SELECT
    DATE_TRUNC('month', order_date)::date AS month,
    SUM(total_amount) AS sales
  FROM cleaned_sales
  WHERE order_status = 'Completed'
  GROUP BY 1
)
SELECT
  month,
  sales,
  LAG(sales) OVER (ORDER BY month) AS prev_month_sales,
  ROUND(100.0 * (sales - LAG(sales) OVER (ORDER BY month)) / NULLIF(LAG(sales) OVER (ORDER BY month),0),2) AS mom_pct_change
FROM monthly
ORDER BY month;

-- ===========================================================================
-- 15) Contribution by customer segment (Consumer, Corporate, etc.)
-- ===========================================================================
SELECT
  c.customer_segment,
  COUNT(DISTINCT s.order_id) AS orders,
  SUM(s.total_amount) AS sales,
  SUM(COALESCE(s.profit_amount,0)) AS profit
FROM cleaned_sales s
LEFT JOIN customers c ON s.customer_id = c.customer_id
WHERE s.order_status = 'Completed'
GROUP BY c.customer_segment
ORDER BY sales DESC;

-- ===========================================================================
-- 16) Sales by Hour of Day (if order_time available)
-- ===========================================================================
-- (Assumes order_date contains time component)
SELECT
  DATE_PART('hour', order_date) AS hour_of_day,
  SUM(total_amount) AS sales,
  COUNT(DISTINCT order_id) AS orders
FROM cleaned_sales
WHERE order_status = 'Completed'
GROUP BY 1
ORDER BY hour_of_day;

-- ===========================================================================
-- 17) Orders and Sales by Payment Method
-- ===========================================================================
SELECT
  payment_method,
  COUNT(DISTINCT order_id) AS orders,
  SUM(total_amount) AS sales
FROM cleaned_sales
WHERE order_status = 'Completed'
GROUP BY payment_method
ORDER BY sales DESC;

-- ===========================================================================
-- 18) Drilldown ready query: product -> category -> sub-category
-- ===========================================================================
SELECT
  COALESCE(p.category,'Unknown') AS category,
  COALESCE(p.sub_category,'Unknown') AS sub_category,
  p.product_id,
  p.product_name,
  SUM(s.total_amount) AS sales,
  SUM(COALESCE(s.profit_amount,0)) AS profit
FROM cleaned_sales s
LEFT JOIN products p ON s.product_id = p.product_id
WHERE s.order_status = 'Completed'
GROUP BY 1,2,3,4
ORDER BY category, sub_category, sales DESC;

-- ===========================================================================
-- 19) Example: Top 10 customers by LTV / Sales in last 12 months
-- ===========================================================================
WITH last_12m AS (
  SELECT * FROM cleaned_sales
  WHERE order_status = 'Completed'
    AND order_date >= (CURRENT_DATE - INTERVAL '365 days')
)
SELECT
  customer_id,
  COUNT(DISTINCT order_id) AS orders,
  SUM(total_amount) AS sales
FROM last_12m
GROUP BY customer_id
ORDER BY sales DESC
LIMIT 10;

-- ===========================================================================
-- 20) Useful: Export a small sample for debugging / Power Query ingestion
-- ===========================================================================
SELECT *
FROM cleaned_sales
WHERE order_date >= (CURRENT_DATE - INTERVAL '90 days')
ORDER BY order_date DESC
LIMIT 1000;

-- ===========================================================================
-- End of file
-- ===========================================================================
