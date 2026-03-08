import { useEffect, useState } from "react";
import { onIdTokenChanged, signInWithPopup, signInWithRedirect, signOut } from "firebase/auth";
import { fetchSymbols } from "./api";
import PriceChart from "./components/PriceChart";
import SymbolSelector from "./components/SymbolSelector";
import Watchlist from "./components/Watchlist";
import { auth, googleProvider } from "./firebase";
import "./App.css";

function App() {
  const [symbols, setSymbols] = useState([]);
  const [selected, setSelected] = useState(null);
  const [user, setUser] = useState(null);
  const [idToken, setIdToken] = useState(null);
  const [authReady, setAuthReady] = useState(false);
  const [authError, setAuthError] = useState("");

  useEffect(() => {
    const unsub = onIdTokenChanged(auth, async (nextUser) => {
      setUser(nextUser);
      if (!nextUser) {
        setIdToken(null);
        setSymbols([]);
        setSelected(null);
        setAuthReady(true);
        return;
      }
      try {
        const token = await nextUser.getIdToken();
        setIdToken(token);
        setAuthError("");
      } catch (err) {
        console.error("Failed to read Firebase ID token:", err);
        setAuthError("Signed in, but failed to read auth token.");
      } finally {
        setAuthReady(true);
      }
    });
    return () => unsub();
  }, []);

  useEffect(() => {
    if (!user) return;
    fetchSymbols().then(setSymbols).catch(console.error);
  }, [user]);

  const handleSignIn = async () => {
    try {
      setAuthError("");
      await signInWithPopup(auth, googleProvider);
    } catch (err) {
      const code = err?.code || "";
      console.error("Firebase sign-in failed:", err);
      if (code === "auth/popup-blocked" || code === "auth/cancelled-popup-request") {
        await signInWithRedirect(auth, googleProvider);
        return;
      }
      if (code === "auth/unauthorized-domain") {
        setAuthError("Unauthorized domain in Firebase Auth settings for this site.");
        return;
      }
      if (code === "auth/operation-not-allowed") {
        setAuthError("Google sign-in is not enabled in Firebase Authentication.");
        return;
      }
      setAuthError(`Sign-in failed (${code || "unknown_error"}).`);
    }
  };

  const handleSignOut = async () => {
    await signOut(auth);
  };

  if (!authReady) {
    return (
      <div className="auth-gate">
        <div className="auth-card">
          <h1>Market Prep Dashboard</h1>
          <p>Checking authentication...</p>
        </div>
      </div>
    );
  }

  if (!user) {
    return (
      <div className="auth-gate">
        <div className="auth-card">
          <h1>Market Prep Dashboard</h1>
          <p>Sign in to continue.</p>
          <button className="auth-btn" onClick={handleSignIn}>
            Sign in with Google
          </button>
          {authError && <p className="auth-error">{authError}</p>}
        </div>
      </div>
    );
  }

  return (
    <div className="app">
      <header className="app-header">
        <h1 className="app-title">Market Prep Dashboard</h1>
        <SymbolSelector symbols={symbols} selected={selected} onSelect={setSelected} />
        <div className="auth-controls">
          {user ? (
            <button className="auth-btn" onClick={handleSignOut}>
              Sign out ({user.email})
            </button>
          ) : (
            <button className="auth-btn" onClick={handleSignIn}>
              Sign in with Google
            </button>
          )}
        </div>
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
          <Watchlist
            onSelect={setSelected}
            idToken={idToken}
            isAuthenticated={Boolean(user)}
          />
        </aside>
      </div>
    </div>
  );
}

export default App;
