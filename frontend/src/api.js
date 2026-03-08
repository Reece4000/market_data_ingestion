/**
 * API client — all calls to the FastAPI backend go through here.
 *
 * In development (npm run dev):
 *   Vite proxies /api → http://localhost:8000, so BASE_URL is empty.
 *
 * In production (Docker / Cloud Run):
 *   VITE_API_URL build arg is passed in at build time.
 */
import axios from "axios";

const BASE_URL = import.meta.env.VITE_API_URL || "";

const api = axios.create({ baseURL: BASE_URL });

const authHeaders = (idToken) =>
  idToken
    ? {
        headers: {
          Authorization: `Bearer ${idToken}`,
        },
      }
    : {};

export const fetchSymbols = () =>
  api.get("/api/symbols").then((r) => r.data);

export const fetchPrices = (symbol, days = 90) =>
  api.get(`/api/prices/${symbol}`, { params: { days } }).then((r) => r.data);

export const fetchIndicators = (symbol, days = 90) =>
  api.get(`/api/indicators/${symbol}`, { params: { days } }).then((r) => r.data);

export const fetchWatchlist = (idToken) =>
  api.get("/api/watchlist", authHeaders(idToken)).then((r) => r.data);

export const addToWatchlist = (symbol, idToken) =>
  api.post("/api/watchlist", { symbol }, authHeaders(idToken)).then((r) => r.data);

export const removeFromWatchlist = (symbol, idToken) =>
  api.delete(`/api/watchlist/${symbol}`, authHeaders(idToken)).then((r) => r.data);
