/**
 * PriceChart — fetches price + indicator data and renders a Recharts LineChart.
 *
 * Recharts key concepts:
 *   ResponsiveContainer  → fills parent width/height
 *   LineChart            → the chart, takes data array + margin
 *   Line                 → one series; dataKey maps to a field in the data array
 *   XAxis / YAxis        → axes with optional formatters
 *   Tooltip / Legend     → built-in interactivity
 */

import { useEffect, useState } from "react";
import {
  CartesianGrid,
  Legend,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
  ReferenceLine,
} from "recharts";
import { fetchIndicators, fetchPrices } from "../api";

const DAYS_OPTIONS = [30, 90, 180, 365];

function PriceChart({ symbol }) {
  const [data, setData] = useState([]);
  const [days, setDays] = useState(90);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  // Overlay toggles
  const [showSMA20, setShowSMA20] = useState(true);
  const [showSMA50, setShowSMA50] = useState(false);
  const [showBB, setShowBB] = useState(false);

  useEffect(() => {
    setLoading(true);
    setError(null);

    Promise.all([fetchPrices(symbol, days), fetchIndicators(symbol, days)])
      .then(([prices, indicators]) => {
        // Merge by date — indicators may have fewer rows (need N periods of history)
        const indicatorMap = Object.fromEntries(indicators.map((i) => [i.date, i]));
        const merged = prices.map((p) => ({ ...p, ...(indicatorMap[p.date] || {}) }));
        setData(merged);
      })
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }, [symbol, days]);

  if (loading) return <div className="loading">Loading {symbol}…</div>;
  if (error) return <div className="error">Error: {error}</div>;

  const latest = data[data.length - 1];

  return (
    <div className="chart-container">
      {/* Header row */}
      <div className="chart-header">
        <h2>{symbol}</h2>
        {latest && (
          <span className="latest-price">${latest.close?.toFixed(2)}</span>
        )}
        <div className="days-toggle">
          {DAYS_OPTIONS.map((d) => (
            <button
              key={d}
              className={days === d ? "active" : ""}
              onClick={() => setDays(d)}
            >
              {d}d
            </button>
          ))}
        </div>
      </div>

      {/* Overlay toggles */}
      <div className="overlay-toggles">
        <label>
          <input type="checkbox" checked={showSMA20} onChange={(e) => setShowSMA20(e.target.checked)} />
          SMA 20
        </label>
        <label>
          <input type="checkbox" checked={showSMA50} onChange={(e) => setShowSMA50(e.target.checked)} />
          SMA 50
        </label>
        <label>
          <input type="checkbox" checked={showBB} onChange={(e) => setShowBB(e.target.checked)} />
          Bollinger Bands
        </label>
      </div>

      {/* Price chart */}
      <ResponsiveContainer width="100%" height={360}>
        <LineChart data={data} margin={{ top: 8, right: 20, left: 0, bottom: 0 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="#2a2a3a" />
          <XAxis
            dataKey="date"
            tick={{ fontSize: 11, fill: "#9ca3af" }}
            tickFormatter={(d) => d.slice(5)} // show MM-DD
            interval="preserveStartEnd"
          />
          <YAxis
            domain={["auto", "auto"]}
            tick={{ fontSize: 11, fill: "#9ca3af" }}
            tickFormatter={(v) => `$${v.toFixed(0)}`}
            width={60}
          />
          <Tooltip
            contentStyle={{ background: "#1e1e2e", border: "1px solid #374151", borderRadius: 6 }}
            labelStyle={{ color: "#e5e7eb" }}
            formatter={(val, name) => [`$${Number(val).toFixed(2)}`, name]}
          />
          <Legend wrapperStyle={{ fontSize: 12 }} />

          <Line type="monotone" dataKey="close" stroke="#3b82f6" dot={false} name="Close" strokeWidth={2} />
          {showSMA20 && <Line type="monotone" dataKey="sma_20" stroke="#f59e0b" dot={false} name="SMA 20" strokeWidth={1.5} />}
          {showSMA50 && <Line type="monotone" dataKey="sma_50" stroke="#10b981" dot={false} name="SMA 50" strokeWidth={1.5} />}
          {showBB && <Line type="monotone" dataKey="bb_upper" stroke="#8b5cf6" dot={false} name="BB Upper" strokeWidth={1} strokeDasharray="4 2" />}
          {showBB && <Line type="monotone" dataKey="bb_lower" stroke="#8b5cf6" dot={false} name="BB Lower" strokeWidth={1} strokeDasharray="4 2" />}
        </LineChart>
      </ResponsiveContainer>

      {/* RSI sub-chart */}
      {data.some((d) => d.rsi_14 != null) && (
        <>
          <p className="sub-label">RSI (14)</p>
          <ResponsiveContainer width="100%" height={120}>
            <LineChart data={data} margin={{ top: 4, right: 20, left: 0, bottom: 0 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="#2a2a3a" />
              <XAxis dataKey="date" hide />
              <YAxis domain={[0, 100]} tick={{ fontSize: 10, fill: "#9ca3af" }} width={60} />
              <Tooltip contentStyle={{ background: "#1e1e2e", border: "1px solid #374151" }} formatter={(v) => [Number(v).toFixed(1), "RSI"]} />
              <ReferenceLine y={70} stroke="#ef4444" strokeDasharray="4 2" label={{ value: "70", fill: "#ef4444", fontSize: 10 }} />
              <ReferenceLine y={30} stroke="#22c55e" strokeDasharray="4 2" label={{ value: "30", fill: "#22c55e", fontSize: 10 }} />
              <Line type="monotone" dataKey="rsi_14" stroke="#a78bfa" dot={false} name="RSI" strokeWidth={1.5} />
            </LineChart>
          </ResponsiveContainer>
        </>
      )}
    </div>
  );
}

export default PriceChart;
