import { useState, useEffect } from "react";
import {
  LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip,
  ResponsiveContainer, BarChart, Bar, Legend
} from "recharts";

const API = import.meta.env.VITE_API_BASE_URL ?? "http://localhost:5001/api";

// ── Types ─────────────────────────────────────────────────────────────────────
interface MonthlyTrend {
  revenueYear:      number;
  revenueMonth:     number;
  orderCount:       number;
  netRevenue:       number;
  uniqueCustomers:  number;
  moM_GrowthPct:    number | null;
  rolling3MonthAvg: number;
}

interface ProductRanking {
  productName:              string;
  categoryName:             string;
  totalRevenue:             number;
  revenueQuartile:          number;
  productTier:              string;
  cumulativeRevenueSharePct: number;
}

interface LowStockItem {
  warehouseName:  string;
  sku:            string;
  productName:    string;
  quantityOnHand: number;
  reorderPoint:   number;
  stockStatus:    string;
}

// ── Helpers ───────────────────────────────────────────────────────────────────
const fmt = (n: number) =>
  new Intl.NumberFormat("en-ZA", { style: "currency", currency: "ZAR", maximumFractionDigits: 0 }).format(n);

const statusColor: Record<string, string> = {
  OUT_OF_STOCK: "#A32D2D",
  CRITICAL:     "#854F0B",
  LOW:          "#3B6D11",
};

// ── App ───────────────────────────────────────────────────────────────────────
export default function App() {
  const [tab,         setTab]         = useState<"revenue" | "products" | "stock">("revenue");
  const [trend,       setTrend]       = useState<MonthlyTrend[]>([]);
  const [products,    setProducts]    = useState<ProductRanking[]>([]);
  const [lowStock,    setLowStock]    = useState<LowStockItem[]>([]);
  const [loading,     setLoading]     = useState(false);
  const [error,       setError]       = useState<string | null>(null);

  useEffect(() => {
    const load = async () => {
      setLoading(true);
      setError(null);
      try {
        if (tab === "revenue") {
          const r = await fetch(`${API}/analytics/revenue/monthly?months=12`);
          setTrend(await r.json());
        } else if (tab === "products") {
          const r = await fetch(`${API}/analytics/products/ranking`);
          setProducts(await r.json());
        } else {
          const r = await fetch(`${API}/inventory/low-stock`);
          setLowStock(await r.json());
        }
      } catch {
        setError("Could not connect to API. Start the backend with `dotnet run`.");
      } finally {
        setLoading(false);
      }
    };
    load();
  }, [tab]);

  return (
    <div style={{ fontFamily: "system-ui, sans-serif", maxWidth: 960, margin: "0 auto", padding: "2rem 1rem" }}>
      <h1 style={{ fontSize: 22, fontWeight: 500, marginBottom: 4 }}>Khulisa Query Explorer</h1>
      <p style={{ color: "#888", fontSize: 13, marginBottom: 24 }}>
        Live views from the KhulisaCommerce Azure SQL database
      </p>

      {/* Tabs */}
      <div style={{ display: "flex", gap: 8, marginBottom: 24 }}>
        {(["revenue", "products", "stock"] as const).map(t => (
          <button
            key={t}
            onClick={() => setTab(t)}
            style={{
              padding: "6px 16px",
              borderRadius: 6,
              border: "0.5px solid",
              borderColor:     tab === t ? "#185FA5" : "#ccc",
              background:      tab === t ? "#E6F1FB" : "transparent",
              color:           tab === t ? "#185FA5" : "#555",
              fontWeight:      tab === t ? 500 : 400,
              cursor: "pointer",
              fontSize: 13,
            }}
          >
            {{ revenue: "Revenue Trend", products: "Product Rankings", stock: "Low Stock" }[t]}
          </button>
        ))}
      </div>

      {error   && <p style={{ color: "#A32D2D", fontSize: 13 }}>{error}</p>}
      {loading && <p style={{ color: "#888", fontSize: 13 }}>Loading…</p>}

      {/* Revenue Trend */}
      {tab === "revenue" && !loading && trend.length > 0 && (
        <div>
          <p style={{ fontSize: 13, color: "#888", marginBottom: 16 }}>
            Monthly net revenue · window function view (LAG, rolling average, YTD)
          </p>
          <ResponsiveContainer width="100%" height={280}>
            <LineChart data={[...trend].reverse()}>
              <CartesianGrid strokeDasharray="3 3" stroke="#eee" />
              <XAxis dataKey={d => `${d.revenueYear}-${String(d.revenueMonth).padStart(2,"0")}`} tick={{ fontSize: 11 }} />
              <YAxis tick={{ fontSize: 11 }} tickFormatter={v => `R${(v/1000).toFixed(0)}k`} />
              <Tooltip formatter={(v: number) => fmt(v)} />
              <Legend />
              <Line type="monotone" dataKey="netRevenue"       name="Net Revenue"    stroke="#185FA5" strokeWidth={2} dot={false} />
              <Line type="monotone" dataKey="rolling3MonthAvg" name="3-Month Avg"    stroke="#854F0B" strokeWidth={1.5} strokeDasharray="4 2" dot={false} />
            </LineChart>
          </ResponsiveContainer>
        </div>
      )}

      {/* Product Rankings */}
      {tab === "products" && !loading && products.length > 0 && (
        <div>
          <p style={{ fontSize: 13, color: "#888", marginBottom: 16 }}>
            NTILE(4) product tiers · cumulative revenue share (Pareto)
          </p>
          <ResponsiveContainer width="100%" height={260}>
            <BarChart data={products.slice(0, 20)}>
              <CartesianGrid strokeDasharray="3 3" stroke="#eee" />
              <XAxis dataKey="productName" tick={{ fontSize: 9 }} interval={0} angle={-30} textAnchor="end" height={60} />
              <YAxis tick={{ fontSize: 11 }} tickFormatter={v => `R${(v/1000).toFixed(0)}k`} />
              <Tooltip formatter={(v: number) => fmt(v)} />
              <Bar dataKey="totalRevenue" name="Revenue" fill="#185FA5" radius={[2,2,0,0]} />
            </BarChart>
          </ResponsiveContainer>
          <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 12, marginTop: 16 }}>
            <thead>
              <tr style={{ borderBottom: "0.5px solid #ddd" }}>
                {["Product","Category","Revenue","Tier","Cumulative %"].map(h => (
                  <th key={h} style={{ textAlign: "left", padding: "6px 8px", color: "#888", fontWeight: 500 }}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {products.slice(0, 15).map((p, i) => (
                <tr key={i} style={{ borderBottom: "0.5px solid #f0f0f0" }}>
                  <td style={{ padding: "6px 8px" }}>{p.productName}</td>
                  <td style={{ padding: "6px 8px", color: "#888" }}>{p.categoryName}</td>
                  <td style={{ padding: "6px 8px" }}>{fmt(p.totalRevenue)}</td>
                  <td style={{ padding: "6px 8px" }}>
                    <span style={{
                      fontSize: 10, padding: "2px 8px", borderRadius: 10,
                      background: p.productTier === "STAR" ? "#E6F1FB" : "#F1EFE8",
                      color:      p.productTier === "STAR" ? "#185FA5" : "#5F5E5A",
                    }}>{p.productTier}</span>
                  </td>
                  <td style={{ padding: "6px 8px", color: p.cumulativeRevenueSharePct <= 80 ? "#185FA5" : "#888" }}>
                    {p.cumulativeRevenueSharePct.toFixed(1)}%
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* Low Stock */}
      {tab === "stock" && !loading && lowStock.length > 0 && (
        <div>
          <p style={{ fontSize: 13, color: "#888", marginBottom: 16 }}>
            Items at or below reorder point — filtered index scan
          </p>
          <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 12 }}>
            <thead>
              <tr style={{ borderBottom: "0.5px solid #ddd" }}>
                {["Status","SKU","Product","Warehouse","On Hand","Reorder Point"].map(h => (
                  <th key={h} style={{ textAlign: "left", padding: "6px 8px", color: "#888", fontWeight: 500 }}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {lowStock.map((s, i) => (
                <tr key={i} style={{ borderBottom: "0.5px solid #f0f0f0" }}>
                  <td style={{ padding: "6px 8px" }}>
                    <span style={{
                      fontSize: 10, padding: "2px 8px", borderRadius: 10,
                      background: s.stockStatus === "OUT_OF_STOCK" ? "#FCEBEB"
                                : s.stockStatus === "CRITICAL"     ? "#FAEEDA" : "#EAF3DE",
                      color: statusColor[s.stockStatus] ?? "#333"
                    }}>{s.stockStatus.replace("_", " ")}</span>
                  </td>
                  <td style={{ padding: "6px 8px", fontFamily: "monospace" }}>{s.sku}</td>
                  <td style={{ padding: "6px 8px" }}>{s.productName}</td>
                  <td style={{ padding: "6px 8px", color: "#888" }}>{s.warehouseName}</td>
                  <td style={{ padding: "6px 8px", fontWeight: 500, color: s.quantityOnHand === 0 ? "#A32D2D" : undefined }}>{s.quantityOnHand}</td>
                  <td style={{ padding: "6px 8px", color: "#888" }}>{s.reorderPoint}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {!loading && (
        (tab === "revenue"  && trend.length   === 0) ||
        (tab === "products" && products.length === 0) ||
        (tab === "stock"    && lowStock.length === 0)
      ) && !error && (
        <p style={{ color: "#888", fontSize: 13 }}>
          No data — make sure the database is seeded and the API is running.
        </p>
      )}
    </div>
  );
}
