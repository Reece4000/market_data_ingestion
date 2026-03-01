function SymbolSelector({ symbols, selected, onSelect }) {
  return (
    <select
      className="symbol-selector"
      value={selected || ""}
      onChange={(e) => onSelect(e.target.value || null)}
    >
      <option value="">— select symbol —</option>
      {symbols.map((s) => (
        <option key={s.symbol} value={s.symbol}>
          {s.symbol} ({s.asset_type})
        </option>
      ))}
    </select>
  );
}

export default SymbolSelector;
