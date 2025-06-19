-- 1. Initial Null Check and Basic Stats
SELECT COUNT(*) AS total_rows,
       COUNT(DISTINCT *) AS distinct_rows
FROM `fraud_sql.raw_data`;

-- 2. Basic Aggregation
SELECT 
  COUNT(*) AS total_rows,
  COUNTIF(Fraud = 1) AS fraud_count,
  ROUND(COUNTIF(Fraud = 1)/COUNT(*), 4) AS fraud_rate,
  MIN(Income) AS min_income,
  MAX(Income) AS max_income,
  ROUND(AVG(Income), 2) AS avg_income,
  COUNT(DISTINCT Credit_card_number) AS unique_cards,
  COUNT(DISTINCT Profession) AS unique_professions
FROM `fraud_sql.raw_data`;

-- 3. Split expiry into month and year
SELECT *,
  SAFE_CAST(SPLIT(Expiry, "/")[OFFSET(0)] AS INT64) AS expiry_month,
  SAFE_CAST(SPLIT(Expiry, "/")[OFFSET(1)] AS INT64) AS expiry_year
FROM `fraud_sql.raw_data`;

-- 4. Calculate card length
SELECT *,
  LENGTH(CAST(Credit_card_number AS STRING)) AS card_length
FROM `fraud_sql.raw_data`;

-- 5. Income category
SELECT *,
  CASE 
    WHEN Income < 30000 THEN 'Low'
    WHEN Income BETWEEN 30000 AND 70000 THEN 'Medium'
    ELSE 'High'
  END AS income_category
FROM `fraud_sql.raw_data`;

-- 6. Fraud Rate per Profession
SELECT 
  Profession,
  COUNT(*) AS total,
  COUNTIF(Fraud = 1) AS frauds,
  ROUND(COUNTIF(Fraud = 1)/COUNT(*), 4) AS fraud_rate
FROM `fraud_sql.raw_data`
GROUP BY Profession;

-- 7. Fraud Rate per Income Category
SELECT 
  income_category,
  COUNT(*) AS total,
  COUNTIF(Fraud = 1) AS frauds,
  ROUND(COUNTIF(Fraud = 1)/COUNT(*), 4) AS fraud_rate
FROM `fraud_sql.cleaned_data`
GROUP BY income_category;

-- 8. Fraud Rate per Card Length
SELECT 
  card_length,
  COUNT(*) AS total,
  COUNTIF(Fraud = 1) AS frauds,
  ROUND(COUNTIF(Fraud = 1)/COUNT(*), 4) AS fraud_rate
FROM `fraud_sql.cleaned_data`
GROUP BY card_length;

-- 9. Profession × Income Category breakdown
SELECT 
  Profession,
  income_category,
  COUNT(*) AS total,
  COUNTIF(Fraud = 1) AS frauds,
  ROUND(COUNTIF(Fraud = 1)/COUNT(*), 4) AS fraud_rate
FROM `fraud_sql.cleaned_data`
GROUP BY Profession, income_category;

-- 10. Create cleaned_data
CREATE OR REPLACE TABLE `fraud_sql.cleaned_data` AS
SELECT *,
  SAFE_CAST(SPLIT(Expiry, "/")[OFFSET(0)] AS INT64) AS expiry_month,
  SAFE_CAST(SPLIT(Expiry, "/")[OFFSET(1)] AS INT64) AS expiry_year,
  LENGTH(CAST(Credit_card_number AS STRING)) AS card_length,
  CASE 
    WHEN Income < 30000 THEN 'Low'
    WHEN Income BETWEEN 30000 AND 70000 THEN 'Medium'
    ELSE 'High'
  END AS income_category
FROM `fraud_sql.raw_data`;

-- 11. Income Rank using Window Function
SELECT *,
  RANK() OVER (PARTITION BY Profession ORDER BY Income DESC) AS income_rank
FROM `fraud_sql.cleaned_data`;

-- 12. Cumulative Fraud Rate
SELECT 
  Income,
  Fraud,
  COUNT(*) OVER (ORDER BY Income) AS cumulative_transactions,
  SUM(Fraud) OVER (ORDER BY Income) AS cumulative_frauds,
  ROUND(SUM(Fraud) OVER (ORDER BY Income) / COUNT(*) OVER (ORDER BY Income), 4) AS running_fraud_rate
FROM `fraud_sql.cleaned_data`
ORDER BY Income;

-- 13. Add fraud_alert_level
CREATE OR REPLACE TABLE `fraud_sql.fraud_enriched_data` AS
SELECT *,
  CASE
    WHEN Fraud = 1 AND income_category = 'High' AND card_length IN (11, 12) THEN 'Critical Fraud Case'
    WHEN Fraud = 1 AND Profession = 'DOCTOR' AND Security_code IN (742, 885, 688) THEN 'Likely Exploited Pattern'
    WHEN Fraud = 1 AND expiry_year >= 34 THEN 'Recent Card Fraud'
    WHEN Fraud = 1 AND card_length < 13 THEN 'Unusual Card Structure'
    WHEN Fraud = 1 THEN 'Generic Fraud'
    ELSE 'Clean Transaction'
  END AS fraud_alert_level
FROM `fraud_sql.cleaned_data`;

-- 14. Fraud Alert Summary
SELECT 
  fraud_alert_level,
  COUNT(*) AS total_cases,
  COUNTIF(Fraud = 1) AS fraud_count,
  ROUND(COUNT(*) / SUM(COUNT(*)) OVER (), 4) AS total_share,
  ROUND(COUNTIF(Fraud = 1) / SUM(COUNTIF(Fraud = 1)) OVER (), 4) AS fraud_share,
  ROUND(AVG(Income), 2) AS avg_income
FROM `fraud_sql.fraud_enriched_data`
GROUP BY fraud_alert_level
ORDER BY fraud_share DESC;

-- 15. Fraud Prioritization Matrix
WITH summary AS (
  SELECT 
    fraud_alert_level,
    COUNT(*) AS total_cases,
    COUNTIF(Fraud = 1) AS fraud_count,
    ROUND(COUNT(*) / SUM(COUNT(*)) OVER (), 4) AS total_share,
    ROUND(COUNTIF(Fraud = 1) / SUM(COUNTIF(Fraud = 1)) OVER (), 4) AS fraud_share,
    ROUND(AVG(Income), 2) AS avg_income
  FROM `fraud_sql.fraud_enriched_data`
  GROUP BY fraud_alert_level
)
SELECT *,
  CASE 
    WHEN fraud_alert_level IN ('Critical Fraud Case', 'Likely Exploited Pattern') THEN 'Immediate'
    WHEN fraud_share > 0.07 AND avg_income > 50000 THEN 'High'
    WHEN fraud_share > 0.04 THEN 'Moderate'
    ELSE 'Low'
  END AS fraud_priority
FROM summary;

-- 16. Fraud Rate per fraud_alert_level × card_length
SELECT 
  fraud_alert_level,
  card_length,
  COUNT(*) AS total_cases,
  COUNTIF(Fraud = 1) AS frauds,
  ROUND(COUNTIF(Fraud = 1)/COUNT(*), 4) AS fraud_rate
FROM `fraud_sql.fraud_enriched_data`
GROUP BY fraud_alert_level, card_length
ORDER BY fraud_alert_level, fraud_rate DESC;

-- 17. Risk Scoring per Transaction
SELECT *,
  (
    IF(Profession = 'ENGINEER', 5, 0) +
    IF(Income < 30000, 15, 0) +
    IF(card_length < 14 OR card_length > 17, 20, 0) +
    IF(expiry_year < 27 OR expiry_year > 33, 10, 0) +
    IF(Security_code IN (742, 688, 167, 660, 367), 25, 0) +
    IF(fraud_alert_level = 'Generic Fraud', 10, 0) +
    IF(fraud_alert_level = 'Recent Card Fraud', 15, 0) +
    IF(fraud_alert_level = 'Critical Fraud Case', 25, 0) +
    IF(Fraud = 1, 30, 0)
  ) AS risk_score
FROM `fraud_sql.fraud_enriched_data`;

-- 18. Security Code Leaderboard
SELECT 
  Security_code,
  COUNT(*) AS total_cases,
  SUM(Fraud) AS fraud_count,
  ROUND(SUM(Fraud) / COUNT(*), 4) AS fraud_rate
FROM `fraud_sql.cleaned_data`
GROUP BY Security_code
HAVING COUNT(*) >= 5
ORDER BY fraud_rate DESC, fraud_count DESC
LIMIT 10;