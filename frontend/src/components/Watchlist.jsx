/**
 * Watchlist — reads/writes symbols to Firestore via the FastAPI watchlist router.
 *
 * This teaches:
 *   - Firestore as a simple persistent key-value / array store
 *   - Optimistic UI updates vs. re-fetch after write
 */
import { useEffect, useState } from "react";
import { addToWatchlist, fetchWatchlist, removeFromWatchlist } from "../api";

function Watchlist({ onSelect, idToken, isAuthenticated }) {
  const [symbols, setSymbols] = useState([]);
  const [input, setInput] = useState("");

  const load = () =>
    fetchWatchlist(idToken)
      .then((d) => setSymbols(d.symbols || []))
      .catch(console.error);

  useEffect(() => {
    if (isAuthenticated && idToken) {
      load();
    } else {
      setSymbols([]);
    }
  }, [idToken, isAuthenticated]);

  const handleAdd = async () => {
    if (!idToken) return;
    const sym = input.trim().toUpperCase();
    if (!sym) return;
    await addToWatchlist(sym, idToken);
    setInput("");
    load();
  };

  const handleRemove = async (sym) => {
    if (!idToken) return;
    await removeFromWatchlist(sym, idToken);
    load();
  };

  return (
    <div className="watchlist">
      <h3>Watchlist</h3>
      {!isAuthenticated && <p className="empty-hint">Sign in to load your watchlist.</p>}
      <div className="watchlist-input">
        <input
          value={input}
          onChange={(e) => setInput(e.target.value.toUpperCase())}
          placeholder="Add ticker…"
          onKeyDown={(e) => e.key === "Enter" && handleAdd()}
          maxLength={10}
          disabled={!isAuthenticated}
        />
        <button onClick={handleAdd} disabled={!isAuthenticated}>
          +
        </button>
      </div>

      {isAuthenticated && symbols.length === 0 && <p className="empty-hint">No symbols yet.</p>}
      <ul className="watchlist-items">
        {symbols.map((sym) => (
          <li key={sym}>
            <button className="sym-btn" onClick={() => onSelect(sym)}>
              {sym}
            </button>
            <button className="remove-btn" onClick={() => handleRemove(sym)} title="Remove">
              ×
            </button>
          </li>
        ))}
      </ul>
    </div>
  );
}

export default Watchlist;
