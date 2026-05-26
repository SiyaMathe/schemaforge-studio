# ERD Design Commentary & Normalisation Walkthrough
## Khulisa Commerce — Database Design Decisions

---

## 1. Design Philosophy

Every design decision below follows a strict set of principles:

- **Surrogate PKs everywhere** — all entities use `INT IDENTITY` PKs. Natural keys (email, product code) are enforced via `UNIQUE` constraints, not as PKs, because natural keys are mutable.
- **No many-to-many without a junction table** — every M:N relationship is resolved with an explicit junction entity that carries its own attributes (e.g. `OrderLine` carries `Quantity` and `UnitPrice`).
- **3NF minimum** — no transitive dependencies. Every non-key attribute depends on the whole key and nothing but the key.
- **Soft deletes** — no physical `DELETE` on business-critical entities. `IsActive BIT` + `DeletedAt DATETIME2` pattern instead.
- **Audit columns** — `CreatedAt` and `UpdatedAt` on every mutable table.

---

## 2. Entity Relationship Overview (UML Notation)

```
Country (1) ─────────────< Province (*)
Province (1) ────────────< City (*)
City (1) ────────────────< Address (*)
Customer (1) ────────────< Address (*)        [1 customer → many addresses]
Customer (1) ────────────< Order (*)          [1 customer → many orders]
Vendor (1) ──────────────< Product (*)        [1 vendor → many products]
Category (1) ────────────< Product (*)        [1 category → many products]
Product (1) ─────────────< ProductVariant (*) [1 product → many variants (size/colour)]
Product (1) ─────────────< ProductImage (*)
Order (1) ───────────────< OrderLine (*)      [junction: resolves Order ↔ ProductVariant M:N]
OrderLine (*) ───────────> ProductVariant (1)
Order (1) ───────────────< Payment (*)
Order (1) ───────────────< Shipment (*)
Shipment (1) ────────────< ShipmentEvent (*)
Courier (1) ─────────────< Shipment (*)
Warehouse (1) ───────────< StockLevel (*)     [junction: resolves Warehouse ↔ ProductVariant M:N]
StockLevel (1) ──────────< StockMovement (*)
Product (*) ─────────────< Review (*)         [via Customer — ternary resolved]
```

---

## 3. Normalisation — Step-by-Step

### Starting Point (Unnormalised Form — UNF)

Imagine a flat spreadsheet exported from the old system:

```
OrderID | CustomerName | CustomerEmail | CustomerCity | ProductName | Category | Qty | Price | VendorName | VendorEmail
1001    | Thabo Nkosi  | t@mail.co.za  | Johannesburg | Air Max 90  | Shoes    | 2   | 1299  | SoleStore   | s@sole.co.za
1001    | Thabo Nkosi  | t@mail.co.za  | Johannesburg | Running Top | Clothing | 1   | 449   | ActiveGear  | a@active.co.za
1002    | Ayanda Dube  | a@mail.co.za  | Durban       | Air Max 90  | Shoes    | 1   | 1299  | SoleStore   | s@sole.co.za
```

**Problems:**
- Repeating groups (multiple products per order row)
- Redundant data (customer info repeated per order line)
- Update anomalies (change VendorEmail in one row, others go stale)

---

### First Normal Form (1NF)

**Rule:** Eliminate repeating groups. Each cell holds one atomic value.

```
OrderID | OrderLineID | CustomerName | CustomerEmail | ProductName | Category | Qty | Price | VendorName
1001    | 1           | Thabo Nkosi  | t@mail.co.za  | Air Max 90  | Shoes    | 2   | 1299  | SoleStore
1001    | 2           | Thabo Nkosi  | t@mail.co.za  | Running Top | Clothing | 1   | 449   | ActiveGear
1002    | 3           | Ayanda Dube  | a@mail.co.za  | Air Max 90  | Shoes    | 1   | 1299  | SoleStore
```

Composite primary key: `(OrderID, OrderLineID)`

**Still broken:** `CustomerName` depends only on `OrderID`, not the full composite key → partial dependency.

---

### Second Normal Form (2NF)

**Rule:** Remove partial dependencies — every non-key attribute must depend on the WHOLE composite key.

Split into:

**Order table** `PK: OrderID`
```
OrderID | CustomerName | CustomerEmail
1001    | Thabo Nkosi  | t@mail.co.za
1002    | Ayanda Dube  | a@mail.co.za
```

**OrderLine table** `PK: (OrderID, OrderLineID)` FK → Order
```
OrderID | OrderLineID | ProductName | Category | Qty | Price | VendorName
1001    | 1           | Air Max 90  | Shoes    | 2   | 1299  | SoleStore
1001    | 2           | Running Top | Clothing | 1   | 449   | ActiveGear
```

**Still broken:** `CustomerEmail` depends on `CustomerName` → transitive dependency (if name changes, email has to change too). Also `Category` depends on `ProductName`, not on the order line key.

---

### Third Normal Form (3NF)

**Rule:** Remove transitive dependencies — non-key attributes must depend on NOTHING but the key.

**Customer table** `PK: CustomerID`
```
CustomerID | CustomerName | CustomerEmail
1          | Thabo Nkosi  | t@mail.co.za
2          | Ayanda Dube  | a@mail.co.za
```

**Order table** `PK: OrderID`, FK → Customer
```
OrderID | CustomerID | OrderDate
1001    | 1          | 2024-01-10
1002    | 2          | 2024-01-11
```

**Category table** `PK: CategoryID`
```
CategoryID | CategoryName
1          | Shoes
2          | Clothing
```

**Product table** `PK: ProductID`, FK → Category, FK → Vendor
```
ProductID | ProductName | CategoryID | VendorID | BasePrice
1         | Air Max 90  | 1          | 1        | 1299
2         | Running Top | 2          | 2        | 449
```

**Vendor table** `PK: VendorID`
```
VendorID | VendorName | VendorEmail
1        | SoleStore  | s@sole.co.za
2        | ActiveGear | a@active.co.za
```

**OrderLine table** `PK: OrderLineID`, FK → Order, FK → Product
```
OrderLineID | OrderID | ProductID | Qty | UnitPrice
1           | 1001    | 1         | 2   | 1299
2           | 1001    | 2         | 1   | 449
3           | 1002    | 1         | 1   | 1299
```

✅ Now in **3NF**: every non-key attribute depends on the key, the whole key, and nothing but the key.

---

## 4. Key Design Decisions

### Why UnitPrice on OrderLine?
`Product.BasePrice` changes over time (sales, price increases). `OrderLine.UnitPrice` captures the price at the time of purchase — this is a deliberate **historical snapshot** pattern, not a 3NF violation. It is a fact about the order line event, not a transitive dependency.

### Why ProductVariant as a separate entity?
Products come in sizes/colours. A `ProductVariant` (SKU) represents one specific purchasable combination (e.g. Air Max 90, Size 10, Black). Stock is tracked at the variant level, not the product level. This correctly models a M:N between Order and ProductVariant, resolved by OrderLine.

### Why Warehouse ↔ ProductVariant as StockLevel?
The same variant can exist in multiple warehouses (Cape Town, Joburg, Durban). `StockLevel` is the junction that carries `QuantityOnHand` as its own attribute — a classic 3NF junction with attributes pattern.

### Province / City hierarchy — why not just one address field?
Enforces referential integrity on geographic data, enables clean regional analytics (sales by province, delivery SLA by city), and avoids free-text inconsistencies like "JHB", "Jhb", "Joburg".
