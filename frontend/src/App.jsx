import { useEffect, useState } from "react";
import { fetchSymbols } from "./api";
import PriceChart from "./components/PriceChart";
import SymbolSelector from "./components/SymbolSelector";
import Watchlist from "./components/Watchlist";
import "./App.css";

function App() {
  const [symbols, setSymbols] = useState([]);
  const [selected, setSelected] = useState(null);

  useEffect(() => {
    fetchSymbols().then(setSymbols).catch(console.error);
  }, []);

  return (
    <div className="app">
      <header className="app-header">
        <h1>Market Prep Dashboard</h1>
        <SymbolSelector symbols={symbols} selected={selected} onSelect={setSelected} />
      </header>

      <div className="app-body">
        <main className="chart-area">
          {selected ? (
            <PriceChart symbol={selected} />
          ) : (
            <div className="empty-state">
              <p>Select a symbol above or click one from your watchlist</p>
            </div>
          )}
        </main>

        <aside className="sidebar">
          <Watchlist onSelect={setSelected} />
        </aside>
      </div>
    </div>
  );
}

export default App;
