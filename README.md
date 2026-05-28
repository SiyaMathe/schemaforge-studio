# SchemaForge Studio
### Enterprise Database Design, Query Engineering & Analytics Portfolio

> **Skills Demonstrated:** 3NF / BCNF Database Normalisation · ERD Design (UML & IDEF1X) · Advanced T-SQL · Stored Procedures · Views & CTEs · Window Functions · Transactions & Locking · Dynamic SQL · NoSQL (MongoDB) · REST API · CI/CD · Docker · Azure SQL

---

## 🧭 What This Project Is

SchemaForge Studio is a full **database engineering showcase** built around a fictional South African e-commerce & logistics platform called **Khulisa Commerce**. It demonstrates every layer of professional database work — from initial ERD and normalisation through to production-grade stored procedures, analytics views, and a REST query API.

---

## 💡 Engineering Problem & Impact

### The Problem
Traditional database portfolios often lack the depth required to demonstrate real-world engineering competency. This project was built to address three specific gaps:
* **Bridging Design and Reality:** Moving beyond simple schemas to implement 3NF/BCNF designs that account for complex business constraints and auditability.
* **Production-Grade Reliability:** Demonstrating that database code requires the same rigour as application code—utilizing pessimistic concurrency, atomic transactions, and automated integration testing.
* **The Analytics Gap:** Implementing professional BI layers that transform raw operational data into actionable strategic insights.

### The Impact
* **High-Integrity Schema:** 20+ tables designed for high-concurrency with strict 3NF compliance.
* **Automated Quality Gates:** A CI/CD pipeline that provisions real SQL Server containers on every PR to validate system integrity via integration tests.
* **Performance Optimization:** Implementation of advanced indexing (Columnstore, Filtered, Composite) and sophisticated window functions to handle complex reporting at scale.

---

## 🗄️ Domain Model — Khulisa Commerce

Khulisa Commerce is a multi-vendor South African e-commerce and last-mile delivery platform.

### Enterprise ERD
![Khulisa Commerce ERD](master%20-%20KhulisaCommerce%20-%20dbo.png)
### Schema Scope
| Domain | Entities |
|--------|----------|
| Users & Auth | Customer, Vendor, Address, Role |
| Catalogue | Category, Product, ProductVariant, ProductImage |
| Orders | Order, OrderLine, OrderStatus, Payment, Discount |
| Inventory | Warehouse, StockLevel, StockMovement |
| Delivery | Courier, Shipment, ShipmentEvent, DeliveryZone |
| Reviews | Review, ReviewHelpful |
| Analytics | SalesSummary (Gold layer) |

---
## 📁 Project Structure

```
schemaforge-studio/
├── backend/
│   ├── sql/
│   │   ├── schema/
│   │   │   ├── 01_erd_commentary.md          # ERD design decisions & normalisation walkthrough
│   │   │   ├── 02_schema_ddl.sql             # Full 3NF schema (DDL)
│   │   │   └── 03_constraints_indexes.sql    # All constraints, indexes, check constraints
│   │   ├── procedures/
│   │   │   ├── 04_order_management.sql       # Order lifecycle stored procedures
│   │   │   ├── 05_inventory_management.sql   # Stock control procedures
│   │   │   └── 06_reporting_procedures.sql   # Dynamic reporting procedures
│   │   ├── views/
│   │   │   ├── 07_operational_views.sql      # Day-to-day operational views
│   │   │   └── 08_analytics_views.sql        # BI/analytics views (window functions)
│   │   ├── queries/
│   │   │   ├── 09_normalisation_showcase.sql # 1NF → 2NF → 3NF steps documented
│   │   │   ├── 10_advanced_queries.sql       # CTEs, subqueries, correlated queries
│   │   │   └── 11_analytics_queries.sql      # ROLLUP, CUBE, PIVOT, ranking
│   │   └── nosql/
│   │       └── 12_mongodb_queries.js         # MongoDB shell — aggregation, $facet, $lookup
│   └── api/
│       ├── Controllers/
│       ├── Models/
│       └── KhulisaQuery.Api.csproj
├── frontend/                                 # React query explorer UI
├── infrastructure/
│   └── main.bicep
├── tests/
│   └── sql/                                  # tSQLt-style unit tests
├── .github/
│   └── workflows/
│       ├── ci.yml
│       └── cd.yml
├── .vscode/
│   ├── extensions.json
│   └── launch.json
├── docker-compose.yml
├── .env.example
└── README.md
```

---

## 🗄️ Domain Model — Khulisa Commerce

Khulisa Commerce is a multi-vendor South African e-commerce and last-mile delivery platform. The schema covers:

| Domain | Entities |
|--------|----------|
| Users & Auth | Customer, Vendor, Address, Role |
| Catalogue | Category, Product, ProductVariant, ProductImage |
| Orders | Order, OrderLine, OrderStatus, Payment, Discount |
| Inventory | Warehouse, StockLevel, StockMovement |
| Delivery | Courier, Shipment, ShipmentEvent, DeliveryZone |
| Reviews | Review, ReviewHelpful |
| Analytics | SalesSummary (Gold layer) |

---

## 🏃 Quick Start

### Prerequisites
- Docker Desktop
- VS Code + recommended extensions (`.vscode/extensions.json`)
- Azure CLI (for cloud deployment)

### Local Dev

```bash
git clone https://github.com/SiyaMathe/schemaforge-studio.git
cd schemaforge-studio

# Spin up SQL Server locally
docker-compose up -d

# Apply schema (order matters)
./scripts/migrate.sh

# Run the query API
cd backend/api && dotnet run
```

---

## 📊 SQL Features by File

| File | Techniques |
|------|-----------|
| `02_schema_ddl.sql` | 3NF schema, surrogate PKs, FKs, CHECK constraints, computed columns |
| `03_constraints_indexes.sql` | Filtered indexes, composite indexes, covering indexes, unique constraints |
| `04_order_management.sql` | Transactions, XACT_ABORT, SAVE TRANSACTION, output params, MERGE |
| `05_inventory_management.sql` | Cursor-free bulk updates, optimistic concurrency, row versioning |
| `06_reporting_procedures.sql` | Dynamic SQL, EXEC sp_executesql, pagination, output params |
| `07_operational_views.sql` | Multi-table joins, CASE expressions, EXISTS/NOT EXISTS |
| `08_analytics_views.sql` | LAG/LEAD, NTILE, PERCENT_RANK, ROWS/RANGE frames, STRING_AGG |
| `09_normalisation_showcase.sql` | Step-by-step 1NF → 2NF → 3NF with comments |
| `10_advanced_queries.sql` | Recursive CTEs, correlated subqueries, CROSS APPLY, FOR JSON |
| `11_analytics_queries.sql` | GROUP BY ROLLUP/CUBE, PIVOT, UNPIVOT, running totals |
| `12_mongodb_queries.js` | Aggregation pipeline, $facet, $lookup, $geoNear, time-series |

---

## ☁️ Deploy to Azure

```bash
# One-time infrastructure setup
az group create --name schemaforge-rg --location southafricanorth
az deployment group create \
  --resource-group schemaforge-rg \
  --template-file infrastructure/main.bicep

# CI/CD runs automatically on push to main
git push origin main
```

### Required GitHub Secrets

| Secret | Where to get it |
|--------|----------------|
| `AZURE_CREDENTIALS` | `az ad sp create-for-rbac --sdk-auth` |
| `AZURE_SQL_CONNECTION_STRING` | Azure Portal → SQL Database → Connection strings |
| `AZURE_WEBAPP_NAME` | Output from Bicep deployment |
| `SQL_ADMIN_PASSWORD` | Set during Bicep deployment |

---

## 🧪 Running SQL Tests

```bash
# Using Docker SQL Server
docker exec -it schemaforge-sql \
  /opt/mssql-tools/bin/sqlcmd \
  -S localhost -U sa -P YourPassword123! \
  -i tests/sql/run_all_tests.sql
```
