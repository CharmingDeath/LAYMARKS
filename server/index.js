const express = require('express');
const cors = require('cors');
const dotenv = require('dotenv');

dotenv.config({ path: require('path').join(__dirname, '..', '.env') });

const app = express();
app.use(cors());

const FMP_KEY = process.env.FMP_API_KEY || '';
const MARKETAUX_KEY = process.env.MARKETAUX_API_KEY || '';

const FMP_STABLE = 'https://financialmodelingprep.com/stable';
const FMP_V3 = 'https://financialmodelingprep.com/api/v3';
const MARKETAUX = 'https://api.marketaux.com/v1/news/all';

const cache = new Map();

function setCache(key, data, ttlMs) {
  cache.set(key, { data, expires: Date.now() + ttlMs });
}

function getCache(key) {
  const item = cache.get(key);
  if (!item) return null;
  if (Date.now() > item.expires) {
    cache.delete(key);
    return null;
  }
  return item.data;
}

async function fetchJson(url) {
  const res = await fetch(url);
  const text = await res.text();
  return { status: res.status, text };
}

app.get('/health', (_, res) => {
  res.json({ ok: true });
});

app.get('/news/world', async (req, res) => {
  const page = req.query.page || '1';
  const key = `world:${page}`;
  const cached = getCache(key);
  if (cached) return res.json(cached);
  if (!MARKETAUX_KEY) return res.status(500).json({ error: 'Missing MARKETAUX_API_KEY' });
  const url = new URL(MARKETAUX);
  url.searchParams.set('api_token', MARKETAUX_KEY);
  url.searchParams.set('language', 'en');
  url.searchParams.set('limit', '100');
  url.searchParams.set('page', page);
  url.searchParams.set('filter_entities', 'true');
  url.searchParams.set('categories', 'business,finance');
  const { status, text } = await fetchJson(url.toString());
  if (status !== 200) return res.status(status).send(text);
  const data = JSON.parse(text);
  setCache(key, data, 5 * 60 * 1000);
  res.json(data);
});

app.get('/news/company', async (_, res) => {
  const key = 'company';
  const cached = getCache(key);
  if (cached) return res.json(cached);
  if (!MARKETAUX_KEY) return res.status(500).json({ error: 'Missing MARKETAUX_API_KEY' });
  const symbols =
    'AAPL,MSFT,TSLA,NVDA,BLK,AMZN,META,GOOGL,BRK.A,BRK.B,JPM,V,MA,TSM,ORCL,IBM,INTC,AMD,BABA,AVGO,ADBE,CRM,CSCO,NFLX,PEP,KO,DIS,NKE,ABNB';
  const url = new URL(MARKETAUX);
  url.searchParams.set('api_token', MARKETAUX_KEY);
  url.searchParams.set('symbols', symbols);
  url.searchParams.set('language', 'en');
  url.searchParams.set('limit', '100');
  url.searchParams.set('filter_entities', 'true');
  url.searchParams.set('must_have_entities', 'true');
  const { status, text } = await fetchJson(url.toString());
  if (status !== 200) return res.status(status).send(text);
  const data = JSON.parse(text);
  setCache(key, data, 5 * 60 * 1000);
  res.json(data);
});

app.get('/market/quote', async (req, res) => {
  const symbols = req.query.symbols || req.query.symbol || '';
  if (!symbols) return res.status(400).json({ error: 'Missing symbols' });
  if (!FMP_KEY) return res.status(500).json({ error: 'Missing FMP_API_KEY' });
  const key = `quote:${symbols}`;
  const cached = getCache(key);
  if (cached) return res.json(cached);

  const list = symbols.split(',').map((s) => s.trim()).filter(Boolean);
  const results = [];
  for (const symbol of list) {
    const stableUrl = `${FMP_STABLE}/quote?symbol=${encodeURIComponent(symbol)}&apikey=${FMP_KEY}`;
    const { status, text } = await fetchJson(stableUrl);
    if (status !== 200) continue;
    const data = JSON.parse(text);
    if (Array.isArray(data) && data.length) {
      results.push(data[0]);
    }
  }
  if (!results.length) return res.status(502).json({ error: 'No quotes returned' });
  setCache(key, results, 60 * 1000);
  res.json(results);
});

app.get('/market/profile', async (req, res) => {
  const symbol = req.query.symbol || '';
  if (!symbol) return res.status(400).json({ error: 'Missing symbol' });
  if (!FMP_KEY) return res.status(500).json({ error: 'Missing FMP_API_KEY' });
  const key = `profile:${symbol}`;
  const cached = getCache(key);
  if (cached) return res.json(cached);

  const stableUrl = `${FMP_STABLE}/profile?symbol=${encodeURIComponent(symbol)}&apikey=${FMP_KEY}`;
  let { status, text } = await fetchJson(stableUrl);
  if (status === 200) {
    const data = JSON.parse(text);
    if (Array.isArray(data) && data.length) {
      setCache(key, data, 30 * 60 * 1000);
      return res.json(data);
    }
  }
  const v3Url = `${FMP_V3}/profile/${encodeURIComponent(symbol)}?apikey=${FMP_KEY}`;
  ({ status, text } = await fetchJson(v3Url));
  if (status !== 200) return res.status(status).send(text);
  const data = JSON.parse(text);
  setCache(key, data, 30 * 60 * 1000);
  res.json(data);
});

app.get('/market/search', async (req, res) => {
  const query = req.query.query || '';
  if (!query) return res.status(400).json({ error: 'Missing query' });
  if (!FMP_KEY) return res.status(500).json({ error: 'Missing FMP_API_KEY' });
  const stableUrl = `${FMP_STABLE}/search-name?query=${encodeURIComponent(query)}&apikey=${FMP_KEY}`;
  let { status, text } = await fetchJson(stableUrl);
  if (status === 200) {
    const data = JSON.parse(text);
    if (Array.isArray(data) && data.length) {
      return res.json(data);
    }
  }
  const v3Url = `${FMP_V3}/search?query=${encodeURIComponent(query)}&limit=50&apikey=${FMP_KEY}`;
  ({ status, text } = await fetchJson(v3Url));
  if (status !== 200) return res.status(status).send(text);
  res.send(text);
});

app.get('/market/listings', async (_, res) => {
  if (!FMP_KEY) return res.status(500).json({ error: 'Missing FMP_API_KEY' });
  const key = 'listings';
  const cached = getCache(key);
  if (cached) return res.json(cached);

  const stableUrl = `${FMP_STABLE}/stock-list?apikey=${FMP_KEY}`;
  let { status, text } = await fetchJson(stableUrl);
  if (status === 200) {
    const data = JSON.parse(text);
    if (Array.isArray(data) && data.length) {
      setCache(key, data, 12 * 60 * 60 * 1000);
      return res.json(data);
    }
  }
  const v3Url = `${FMP_V3}/stock/list?apikey=${FMP_KEY}`;
  ({ status, text } = await fetchJson(v3Url));
  if (status !== 200) return res.status(status).send(text);
  const data = JSON.parse(text);
  setCache(key, data, 12 * 60 * 60 * 1000);
  res.json(data);
});

app.get('/market/peers', async (req, res) => {
  if (!FMP_KEY) return res.status(500).json({ error: 'Missing FMP_API_KEY' });
  const sector = req.query.sector || '';
  if (!sector) return res.status(400).json({ error: 'Missing sector' });
  const key = `peers:${sector}`;
  const cached = getCache(key);
  if (cached) return res.json(cached);

  const url = new URL(`${FMP_STABLE}/stock-screener`);
  url.searchParams.set('sector', sector);
  url.searchParams.set('limit', '20');
  url.searchParams.set('apikey', FMP_KEY);
  const { status, text } = await fetchJson(url.toString());
  if (status !== 200) return res.status(status).send(text);
  const data = JSON.parse(text);
  setCache(key, data, 6 * 60 * 60 * 1000);
  res.json(data);
});

app.get('/calendar/economic', async (req, res) => {
  if (!FMP_KEY) return res.status(500).json({ error: 'Missing FMP_API_KEY' });
  const from = req.query.from || '';
  const to = req.query.to || '';
  const key = `econ:${from}:${to}`;
  const cached = getCache(key);
  if (cached) return res.json(cached);

  const url = new URL(`${FMP_STABLE}/economic-calendar`);
  if (from) url.searchParams.set('from', from);
  if (to) url.searchParams.set('to', to);
  url.searchParams.set('apikey', FMP_KEY);
  const { status, text } = await fetchJson(url.toString());
  if (status !== 200) return res.status(status).send(text);
  const data = JSON.parse(text);
  setCache(key, data, 30 * 60 * 1000);
  res.json(data);
});

app.get('/calendar/earnings', async (req, res) => {
  if (!FMP_KEY) return res.status(500).json({ error: 'Missing FMP_API_KEY' });
  const from = req.query.from || '';
  const to = req.query.to || '';
  const key = `earn:${from}:${to}`;
  const cached = getCache(key);
  if (cached) return res.json(cached);

  const url = new URL(`${FMP_STABLE}/earnings-calendar`);
  if (from) url.searchParams.set('from', from);
  if (to) url.searchParams.set('to', to);
  url.searchParams.set('apikey', FMP_KEY);
  const { status, text } = await fetchJson(url.toString());
  if (status !== 200) return res.status(status).send(text);
  const data = JSON.parse(text);
  setCache(key, data, 30 * 60 * 1000);
  res.json(data);
});

app.get('/market/history', async (req, res) => {
  if (!FMP_KEY) return res.status(500).json({ error: 'Missing FMP_API_KEY' });
  const symbol = req.query.symbol || '';
  if (!symbol) return res.status(400).json({ error: 'Missing symbol' });
  const from = req.query.from || '';
  const to = req.query.to || '';
  const key = `history:${symbol}:${from}:${to}`;
  const cached = getCache(key);
  if (cached) return res.json(cached);

  const lightUrl = new URL(`${FMP_STABLE}/historical-price-eod/light`);
  lightUrl.searchParams.set('symbol', symbol);
  if (from) lightUrl.searchParams.set('from', from);
  if (to) lightUrl.searchParams.set('to', to);
  lightUrl.searchParams.set('apikey', FMP_KEY);
  let { status, text } = await fetchJson(lightUrl.toString());
  if (status === 200) {
    const data = JSON.parse(text);
    if (Array.isArray(data) && data.length) {
      setCache(key, data, 6 * 60 * 60 * 1000);
      return res.json(data);
    }
  }

  const fullUrl = new URL(`${FMP_STABLE}/historical-price-eod/full`);
  fullUrl.searchParams.set('symbol', symbol);
  if (from) fullUrl.searchParams.set('from', from);
  if (to) fullUrl.searchParams.set('to', to);
  fullUrl.searchParams.set('apikey', FMP_KEY);
  ({ status, text } = await fetchJson(fullUrl.toString()));
  if (status !== 200) return res.status(status).send(text);
  const data = JSON.parse(text);
  setCache(key, data, 6 * 60 * 60 * 1000);
  res.json(data);
});

const PORT = process.env.PORT || 8787;
app.listen(PORT, () => {
  console.log(`APPMINE proxy running on http://localhost:${PORT}`);
});
