const express = require('express');
const cors = require('cors');
const dotenv = require('dotenv');

dotenv.config({ path: require('path').join(__dirname, '..', '.env') });

const app = express();
app.use(cors());

const FMP_KEY = process.env.FMP_API_KEY || '';
const MARKETAUX_KEY = process.env.MARKETAUX_API_KEY || '';
const NEWSAPI_KEY = process.env.NEWSAPI_KEY || '';
const ALPHAVANTAGE_KEY = process.env.ALPHAVANTAGE_API_KEY || '';

const FMP_STABLE = 'https://financialmodelingprep.com/stable';
const FMP_V3 = 'https://financialmodelingprep.com/api/v3';
const MARKETAUX = 'https://api.marketaux.com/v1/news/all';
const NEWSAPI_BASE = 'https://newsapi.org/v2';
const ALPHAVANTAGE_BASE = 'https://www.alphavantage.co/query';

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

function safeJsonParse(text, fallback = null) {
  try {
    return JSON.parse(text);
  } catch (_) {
    return fallback;
  }
}

async function fetchJson(url) {
  const res = await fetch(url);
  const text = await res.text();
  return { status: res.status, text };
}

async function fetchArray(url) {
  try {
    const { status, text } = await fetchJson(url);
    if (status !== 200) return [];
    const parsed = safeJsonParse(text, []);
    return Array.isArray(parsed) ? parsed : [];
  } catch (_) {
    return [];
  }
}

function parseCsvLine(line) {
  const fields = [];
  let current = '';
  let inQuotes = false;

  for (let i = 0; i < line.length; i += 1) {
    const ch = line[i];
    if (ch === '"') {
      inQuotes = !inQuotes;
      continue;
    }
    if (ch === ',' && !inQuotes) {
      fields.push(current.trim());
      current = '';
      continue;
    }
    current += ch;
  }
  fields.push(current.trim());
  return fields;
}

async function fetchAlphaListings() {
  if (!ALPHAVANTAGE_KEY) return [];
  try {
    const url = new URL(ALPHAVANTAGE_BASE);
    url.searchParams.set('function', 'LISTING_STATUS');
    url.searchParams.set('state', 'active');
    url.searchParams.set('apikey', ALPHAVANTAGE_KEY);

    const { status, text } = await fetchJson(url.toString());
    if (status !== 200 || !text) return [];
    if (text.includes('Error Message') || text.includes('Note')) return [];

    const cleaned = text.replace(/^\uFEFF/, '');
    const lines = cleaned.split('\n').map((line) => line.trim()).filter(Boolean);
    if (lines.length <= 1) return [];

    const header = parseCsvLine(lines[0]).map((value) =>
      value.replace(/^\uFEFF/, '').toLowerCase(),
    );
    const symbolIndex = header.findIndex((value) => value === 'symbol');
    const nameIndex = header.findIndex((value) => value === 'name');
    const exchangeIndex = header.findIndex(
      (value) => value === 'exchange' || value === 'assettype',
    );
    if (symbolIndex < 0 || nameIndex < 0 || exchangeIndex < 0) return [];

    const rows = [];
    for (let i = 1; i < lines.length; i += 1) {
      const fields = parseCsvLine(lines[i]);
      const symbol = (fields[symbolIndex] || '').trim();
      if (!symbol) continue;
      const name = (fields[nameIndex] || symbol).trim();
      const exchange = normalizeExchangeLabel(fields[exchangeIndex] || '');
      rows.push({
        symbol,
        name,
        exchange,
        exchangeShortName: exchange,
      });
    }
    return rows;
  } catch (_) {
    return [];
  }
}

function normalizeExchangeLabel(exchange) {
  const raw = (exchange || '').toString().trim();
  const upper = raw.toUpperCase();
  if (!upper) return '';
  if (upper.includes('NEW YORK') || upper.includes('NYSE')) return 'NYSE';
  if (upper.includes('NASDAQ')) return 'NASDAQ';
  if (upper.includes('LONDON') || upper.includes('LSE')) return 'LSE';
  return upper;
}

function isTargetExchange(exchange, allowed = ['NYSE', 'LSE']) {
  const normalized = normalizeExchangeLabel(exchange);
  const allow = allowed.map((x) => x.toUpperCase());
  if (!normalized || normalized === 'US') {
    return allow.includes('NYSE') || allow.includes('NASDAQ') || allow.includes('US');
  }
  if (allow.includes('NYSE') && normalized.includes('NYSE')) return true;
  if (allow.includes('LSE') && normalized.includes('LSE')) return true;
  if (allow.includes('NASDAQ') && normalized.includes('NASDAQ')) return true;
  return allow.some((item) => normalized.includes(item));
}

function normalizeListingItem(item) {
  if (!item || typeof item !== 'object') return null;
  const symbol = (item.symbol || '').toString().trim();
  if (!symbol) return null;
  const name = (item.name || item.companyName || '').toString().trim() || symbol;
  const exchange = normalizeExchangeLabel(
    item.exchangeShortName || item.exchange || item.exchangeName || item.market || item.region || '',
  ) || 'US';
  return {
    ...item,
    symbol,
    name,
    exchange,
    exchangeShortName: exchange,
  };
}

function dedupeListings(items) {
  const deduped = [];
  const seen = new Set();
  for (const raw of items) {
    const item = normalizeListingItem(raw);
    if (!item) continue;
    const key = `${item.symbol}|${item.exchange}`;
    if (seen.has(key)) continue;
    seen.add(key);
    deduped.push(item);
  }
  return deduped;
}

function normalizeWords(input) {
  return (input || '')
    .toString()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

function levenshteinDistance(a, b) {
  if (a === b) return 0;
  if (!a) return b.length;
  if (!b) return a.length;
  const prev = new Array(b.length + 1);
  const next = new Array(b.length + 1);
  for (let j = 0; j <= b.length; j++) prev[j] = j;
  for (let i = 1; i <= a.length; i++) {
    next[0] = i;
    for (let j = 1; j <= b.length; j++) {
      const cost = a.charCodeAt(i - 1) === b.charCodeAt(j - 1) ? 0 : 1;
      next[j] = Math.min(next[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost);
    }
    for (let j = 0; j <= b.length; j++) prev[j] = next[j];
  }
  return prev[b.length];
}

function fuzzyMatchListing(item, query) {
  const normalizedQuery = normalizeWords(query);
  if (!normalizedQuery) return false;

  const haystack = normalizeWords(`${item.symbol} ${item.name} ${item.exchange}`);
  if (!haystack) return false;
  if (haystack.includes(normalizedQuery)) return true;

  const queryTokens = normalizedQuery.split(' ').filter((token) => token.length >= 3);
  if (!queryTokens.length) return false;

  const targetTokens = haystack.split(' ').filter((token) => token.length >= 2);
  let hitCount = 0;

  for (const qToken of queryTokens) {
    const matched = targetTokens.some((token) => {
      if (token.startsWith(qToken) || qToken.startsWith(token)) return true;
      if (qToken.length < 5 || token.length < 4) return false;
      if (Math.abs(qToken.length - token.length) > 1) return false;
      return levenshteinDistance(qToken, token) <= 1;
    });
    if (matched) hitCount += 1;
  }

  return hitCount >= Math.max(1, Math.ceil(queryTokens.length * 0.7));
}

function toMarketauxFromNewsApi(item) {
  return {
    title: item.title || 'Untitled',
    description: item.description || '',
    image_url: item.urlToImage || '',
    source: item.source && item.source.name ? item.source.name : 'NewsAPI',
    published_at: item.publishedAt || '',
    url: item.url || '',
    snippet: item.content || item.description || '',
  };
}

function toMarketauxFromFmp(item) {
  return {
    title: item.title || 'Untitled',
    description: item.text || '',
    image_url: item.image || '',
    source: item.site || 'Company News',
    published_at: item.publishedDate || '',
    url: item.url || '',
    snippet: item.text || '',
  };
}

async function fetchMarketauxNews(params) {
  if (!MARKETAUX_KEY) return [];
  const url = new URL(MARKETAUX);
  url.searchParams.set('api_token', MARKETAUX_KEY);
  for (const [key, value] of Object.entries(params)) {
    if (value === undefined || value === null || value === '') continue;
    url.searchParams.set(key, String(value));
  }
  const { status, text } = await fetchJson(url.toString());
  if (status !== 200) return [];
  const data = safeJsonParse(text, {});
  const rows = data && Array.isArray(data.data) ? data.data : [];
  return rows;
}

async function fetchNewsApiTopBusiness(page = 1, pageSize = 60) {
  if (!NEWSAPI_KEY) return [];
  const url = new URL(`${NEWSAPI_BASE}/top-headlines`);
  url.searchParams.set('category', 'business');
  url.searchParams.set('language', 'en');
  url.searchParams.set('page', String(page));
  url.searchParams.set('pageSize', String(pageSize));
  url.searchParams.set('apiKey', NEWSAPI_KEY);
  const { status, text } = await fetchJson(url.toString());
  if (status !== 200) return [];
  const data = safeJsonParse(text, {});
  if (!data || data.status !== 'ok' || !Array.isArray(data.articles)) return [];
  return data.articles.map(toMarketauxFromNewsApi);
}

async function fetchNewsApiCompany(symbols, page = 1, pageSize = 80) {
  if (!NEWSAPI_KEY) return [];
  const symbolList = symbols
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean)
    .slice(0, 25);
  if (!symbolList.length) return [];

  const url = new URL(`${NEWSAPI_BASE}/everything`);
  url.searchParams.set('q', symbolList.join(' OR '));
  url.searchParams.set('language', 'en');
  url.searchParams.set('sortBy', 'publishedAt');
  url.searchParams.set('page', String(page));
  url.searchParams.set('pageSize', String(pageSize));
  url.searchParams.set('apiKey', NEWSAPI_KEY);
  const { status, text } = await fetchJson(url.toString());
  if (status !== 200) return [];
  const data = safeJsonParse(text, {});
  if (!data || data.status !== 'ok' || !Array.isArray(data.articles)) return [];
  return data.articles.map(toMarketauxFromNewsApi);
}

async function fetchFmpCompanyNews(symbols, limit = 100) {
  if (!FMP_KEY) return [];
  const candidates = [
    `${FMP_STABLE}/stock-news?tickers=${encodeURIComponent(symbols)}&limit=${limit}&apikey=${FMP_KEY}`,
    `${FMP_STABLE}/stock_news?tickers=${encodeURIComponent(symbols)}&limit=${limit}&apikey=${FMP_KEY}`,
    `${FMP_V3}/stock_news?tickers=${encodeURIComponent(symbols)}&limit=${limit}&apikey=${FMP_KEY}`,
  ];

  for (const url of candidates) {
    const data = await fetchArray(url);
    if (data.length) {
      return data.map(toMarketauxFromFmp);
    }
  }
  return [];
}

async function fetchListingsFromProviders() {
  const combined = [];
  if (FMP_KEY) {
    combined.push(...(await fetchArray(`${FMP_STABLE}/stock-list?apikey=${FMP_KEY}`)));
    combined.push(...(await fetchArray(`${FMP_V3}/stock/list?apikey=${FMP_KEY}`)));

    if (combined.length < 3000) {
      for (const exchange of ['NYSE', 'LSE']) {
        const stableScreenUrl = new URL(`${FMP_STABLE}/stock-screener`);
        stableScreenUrl.searchParams.set('exchange', exchange);
        stableScreenUrl.searchParams.set('limit', '10000');
        stableScreenUrl.searchParams.set('apikey', FMP_KEY);
        combined.push(...(await fetchArray(stableScreenUrl.toString())));

        const v3ScreenUrl = new URL(`${FMP_V3}/stock-screener`);
        v3ScreenUrl.searchParams.set('exchange', exchange);
        v3ScreenUrl.searchParams.set('limit', '10000');
        v3ScreenUrl.searchParams.set('apikey', FMP_KEY);
        combined.push(...(await fetchArray(v3ScreenUrl.toString())));
      }
    }
  }

  let deduped = dedupeListings(combined);
  const targetCount = deduped.filter((item) =>
    isTargetExchange(item.exchange, ['NYSE', 'LSE']),
  ).length;

  if (targetCount < 1200) {
    combined.push(...(await fetchAlphaListings()));
    deduped = dedupeListings(combined);
  }

  return deduped;
}

async function getCachedListings() {
  const key = 'listings:all';
  const cached = getCache(key);
  if (cached) return cached;
  const listings = await fetchListingsFromProviders();
  setCache(key, listings, 12 * 60 * 60 * 1000);
  return listings;
}

function dedupeBySymbolExchange(items) {
  const out = [];
  const seen = new Set();
  for (const raw of items) {
    const item = normalizeListingItem(raw);
    if (!item) continue;
    const key = `${item.symbol}|${item.exchange}`;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(item);
  }
  return out;
}

app.get('/health', (_, res) => {
  res.json({ ok: true });
});

app.get('/news/world', async (req, res) => {
  try {
    const page = Number(req.query.page || 1);
    const key = `world:${page}`;
    const cached = getCache(key);
    if (cached) return res.json(cached);

    let articles = await fetchMarketauxNews({
      language: 'en',
      limit: 100,
      page,
      filter_entities: 'true',
      categories: 'business,finance',
    });

    if (!articles.length) {
      articles = await fetchNewsApiTopBusiness(page, 80);
    }

    if (!articles.length) {
      const fallbackSymbols =
        'AAPL,MSFT,TSLA,NVDA,AMZN,META,GOOGL,JPM,V,MA,BRK.B,SPY,QQQ';
      articles = await fetchFmpCompanyNews(fallbackSymbols, 100);
    }

    if (!articles.length) {
      return res.status(502).json({ error: 'No world news returned from providers' });
    }

    const payload = { data: articles };
    setCache(key, payload, 5 * 60 * 1000);
    return res.json(payload);
  } catch (error) {
    return res.status(500).json({ error: error.message || 'World news error' });
  }
});

app.get('/news/company', async (req, res) => {
  try {
    const requestedSymbols = (req.query.symbols || req.query.symbol || '').toString().trim();
    const limit = Number(req.query.limit || 100);
    const symbols =
      requestedSymbols ||
      'AAPL,MSFT,TSLA,NVDA,BLK,AMZN,META,GOOGL,BRK.A,BRK.B,JPM,V,MA,TSM,ORCL,IBM,INTC,AMD,BABA,AVGO,ADBE,CRM,CSCO,NFLX,PEP,KO,DIS,NKE,ABNB';

    const key = `company:${symbols}:${limit}`;
    const cached = getCache(key);
    if (cached) return res.json(cached);

    let articles = await fetchMarketauxNews({
      symbols,
      language: 'en',
      limit,
      filter_entities: 'true',
      must_have_entities: 'true',
    });

    if (!articles.length) {
      articles = await fetchFmpCompanyNews(symbols, limit);
    }

    if (!articles.length) {
      articles = await fetchNewsApiCompany(symbols, 1, Math.min(limit, 100));
    }

    if (!articles.length) {
      return res.status(502).json({ error: 'No company news returned from providers' });
    }

    const payload = { data: articles };
    setCache(key, payload, 5 * 60 * 1000);
    return res.json(payload);
  } catch (error) {
    return res.status(500).json({ error: error.message || 'Company news error' });
  }
});

app.get('/market/quote', async (req, res) => {
  const symbols = (req.query.symbols || req.query.symbol || '').toString().trim();
  if (!symbols) return res.status(400).json({ error: 'Missing symbols' });
  if (!FMP_KEY) return res.status(500).json({ error: 'Missing FMP_API_KEY' });

  const key = `quote:${symbols}`;
  const cached = getCache(key);
  if (cached) return res.json(cached);

  const list = symbols.split(',').map((s) => s.trim()).filter(Boolean);
  const rows = [];
  const seen = new Set();

  for (const symbol of list) {
    const candidates = [
      `${FMP_STABLE}/quote?symbol=${encodeURIComponent(symbol)}&apikey=${FMP_KEY}`,
      `${FMP_STABLE}/quote?symbols=${encodeURIComponent(symbol)}&apikey=${FMP_KEY}`,
      `${FMP_V3}/quote/${encodeURIComponent(symbol)}?apikey=${FMP_KEY}`,
    ];

    for (const url of candidates) {
      const data = await fetchArray(url);
      if (!data.length) continue;
      const item = data[0];
      const keyName = (item.symbol || symbol).toString().toUpperCase();
      if (seen.has(keyName)) break;
      seen.add(keyName);
      rows.push(item);
      break;
    }
  }

  if (!rows.length) {
    return res.status(502).json({ error: 'No quotes returned' });
  }

  setCache(key, rows, 60 * 1000);
  return res.json(rows);
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
    const data = safeJsonParse(text, []);
    if (Array.isArray(data) && data.length) {
      setCache(key, data, 30 * 60 * 1000);
      return res.json(data);
    }
  }
  const v3Url = `${FMP_V3}/profile/${encodeURIComponent(symbol)}?apikey=${FMP_KEY}`;
  ({ status, text } = await fetchJson(v3Url));
  if (status !== 200) return res.status(status).send(text);
  const data = safeJsonParse(text, []);
  setCache(key, data, 30 * 60 * 1000);
  return res.json(data);
});

app.get('/market/search', async (req, res) => {
  const query = (req.query.query || '').toString().trim();
  if (!query) return res.status(400).json({ error: 'Missing query' });
  const requestedLimit = Number(req.query.limit || 120);
  const limit = Number.isFinite(requestedLimit)
    ? Math.min(300, Math.max(1, Math.floor(requestedLimit)))
    : 120;
  const exchangeQuery = (req.query.exchange || 'NYSE,NASDAQ,LSE').toString();
  const allowed = exchangeQuery
    .split(',')
    .map((x) => x.trim().toUpperCase())
    .filter(Boolean);

  const merged = [];

  if (FMP_KEY) {
    const stableNameUrl = `${FMP_STABLE}/search-name?query=${encodeURIComponent(query)}&apikey=${FMP_KEY}`;
    merged.push(...(await fetchArray(stableNameUrl)));

    const stableSymbolUrl = `${FMP_STABLE}/search-symbol?query=${encodeURIComponent(query)}&apikey=${FMP_KEY}`;
    merged.push(...(await fetchArray(stableSymbolUrl)));

    const v3Url = `${FMP_V3}/search?query=${encodeURIComponent(query)}&limit=120&apikey=${FMP_KEY}`;
    merged.push(...(await fetchArray(v3Url)));
  }

  const listings = await getCachedListings();
  const listingMatches = listings.filter((item) => {
    const q = normalizeWords(query);
    const text = normalizeWords(`${item.symbol} ${item.name} ${item.exchange}`);
    return text.includes(q) || fuzzyMatchListing(item, query);
  });
  merged.push(...listingMatches.slice(0, Math.max(limit, 120)));

  const deduped = dedupeBySymbolExchange(merged)
    .filter((item) => isTargetExchange(item.exchange, allowed))
    .slice(0, limit);

  return res.json(deduped);
});

app.get('/market/nyse-directory', async (req, res) => {
  if (!FMP_KEY && !ALPHAVANTAGE_KEY) {
    return res.status(500).json({ error: 'Missing FMP_API_KEY or ALPHAVANTAGE_API_KEY' });
  }

  const query = (req.query.query || '').toString().trim();
  const exchangeQuery = (req.query.exchange || 'NYSE').toString();
  const allowed = exchangeQuery
    .split(',')
    .map((x) => x.trim().toUpperCase())
    .filter(Boolean);

  const pageRaw = Number(req.query.page || 1);
  const limitRaw = Number(req.query.limit || 100);
  const page = Number.isFinite(pageRaw) ? Math.max(1, Math.floor(pageRaw)) : 1;
  const limit = Number.isFinite(limitRaw)
    ? Math.min(300, Math.max(1, Math.floor(limitRaw)))
    : 100;

  const listings = await getCachedListings();
  if (!listings.length) {
    return res.status(502).json({ error: 'No listings returned' });
  }

  let filtered = listings.filter((item) => isTargetExchange(item.exchange, allowed));

  if (query) {
    const normalizedQuery = normalizeWords(query);
    filtered = filtered.filter((item) => {
      const text = normalizeWords(`${item.symbol} ${item.name} ${item.exchange}`);
      return text.includes(normalizedQuery) || fuzzyMatchListing(item, query);
    });
  }

  filtered = dedupeBySymbolExchange(filtered).sort((a, b) =>
    a.symbol.toString().localeCompare(b.symbol.toString()),
  );

  const total = filtered.length;
  const totalPages = total == 0 ? 0 : Math.ceil(total / limit);
  const safePage = totalPages == 0 ? 1 : Math.min(page, totalPages);
  const start = (safePage - 1) * limit;
  const data = filtered.slice(start, start + limit);

  return res.json({
    data,
    meta: {
      query,
      exchange: allowed.join(','),
      page: safePage,
      limit,
      total,
      totalPages,
    },
  });
});

app.get('/market/listings', async (req, res) => {
  if (!FMP_KEY && !ALPHAVANTAGE_KEY) {
    return res.status(500).json({ error: 'Missing FMP_API_KEY or ALPHAVANTAGE_API_KEY' });
  }

  const exchangeQuery = (req.query.exchange || 'NYSE,NASDAQ,LSE').toString();
  const allowed = exchangeQuery
    .split(',')
    .map((x) => x.trim().toUpperCase())
    .filter(Boolean);

  const listings = await getCachedListings();
  if (!listings.length) {
    return res.status(502).json({ error: 'No listings returned' });
  }

  const filtered = allowed.length
    ? listings.filter((item) => isTargetExchange(item.exchange, allowed))
    : listings;

  return res.json(filtered);
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
  const data = safeJsonParse(text, []);
  setCache(key, data, 6 * 60 * 60 * 1000);
  res.json(data);
});

app.get('/market/financials', async (req, res) => {
  if (!FMP_KEY) return res.status(500).json({ error: 'Missing FMP_API_KEY' });
  const symbol = (req.query.symbol || '').toString().trim();
  const periodRaw = (req.query.period || 'quarter').toString().trim().toLowerCase();
  const period = periodRaw === 'annual' || periodRaw === 'year' ? 'annual' : 'quarter';
  if (!symbol) return res.status(400).json({ error: 'Missing symbol' });

  const key = `financials:${symbol}:${period}`;
  const cached = getCache(key);
  if (cached) return res.json(cached);

  const queryPeriod = period === 'quarter' ? 'quarter' : 'annual';
  const queryLimit = period === 'quarter' ? '8' : '6';

  async function fetchStatement(type) {
    const stableUrl = new URL(`${FMP_STABLE}/${type}`);
    stableUrl.searchParams.set('symbol', symbol);
    stableUrl.searchParams.set('period', queryPeriod);
    stableUrl.searchParams.set('limit', queryLimit);
    stableUrl.searchParams.set('apikey', FMP_KEY);
    let { status, text } = await fetchJson(stableUrl.toString());
    if (status === 200) {
      const stableData = safeJsonParse(text, []);
      if (Array.isArray(stableData) && stableData.length) {
        return stableData;
      }
    }

    const v3Url = new URL(`${FMP_V3}/${type}/${encodeURIComponent(symbol)}`);
    v3Url.searchParams.set('period', queryPeriod);
    v3Url.searchParams.set('limit', queryLimit);
    v3Url.searchParams.set('apikey', FMP_KEY);
    ({ status, text } = await fetchJson(v3Url.toString()));
    if (status !== 200) return null;
    const v3Data = safeJsonParse(text, []);
    return Array.isArray(v3Data) ? v3Data : null;
  }

  const [income, balance, cashflow] = await Promise.all([
    fetchStatement('income-statement'),
    fetchStatement('balance-sheet-statement'),
    fetchStatement('cash-flow-statement'),
  ]);

  if (!income && !balance && !cashflow) {
    return res.status(502).json({ error: 'No financial statements returned' });
  }

  const payload = {
    symbol,
    period: queryPeriod,
    income: income || [],
    balance: balance || [],
    cashflow: cashflow || [],
  };
  setCache(key, payload, 6 * 60 * 60 * 1000);
  res.json(payload);
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
  const data = safeJsonParse(text, []);
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
  const data = safeJsonParse(text, []);
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
    const data = safeJsonParse(text, []);
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
  const data = safeJsonParse(text, []);
  setCache(key, data, 6 * 60 * 60 * 1000);
  res.json(data);
});

app.get('/market/intraday', async (req, res) => {
  if (!FMP_KEY) return res.status(500).json({ error: 'Missing FMP_API_KEY' });
  const symbol = req.query.symbol || '';
  const interval = req.query.interval || '1hour';
  if (!symbol) return res.status(400).json({ error: 'Missing symbol' });
  const key = `intraday:${symbol}:${interval}`;
  const cached = getCache(key);
  if (cached) return res.json(cached);

  const stableUrl = new URL(`${FMP_STABLE}/historical-chart/${interval}`);
  stableUrl.searchParams.set('symbol', symbol);
  stableUrl.searchParams.set('apikey', FMP_KEY);
  let { status, text } = await fetchJson(stableUrl.toString());
  if (status === 200) {
    const data = safeJsonParse(text, []);
    if (Array.isArray(data) && data.length) {
      setCache(key, data, 10 * 60 * 1000);
      return res.json(data);
    }
  }

  const v3Url = new URL(`${FMP_V3}/historical-chart/${interval}/${encodeURIComponent(symbol)}`);
  v3Url.searchParams.set('apikey', FMP_KEY);
  ({ status, text } = await fetchJson(v3Url.toString()));
  if (status !== 200) return res.status(status).send(text);
  const data = safeJsonParse(text, []);
  setCache(key, data, 10 * 60 * 1000);
  res.json(data);
});

const PORT = process.env.PORT || 8787;
const HOST = process.env.HOST || '0.0.0.0';
app.listen(PORT, HOST, () => {
  console.log(`APPMINE proxy running on http://${HOST}:${PORT}`);
});
