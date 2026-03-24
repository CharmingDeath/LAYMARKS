import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import 'models.dart';

class AppSecrets {
  static String get newsApiKey => dotenv.env['NEWSAPI_KEY'] ?? '';
  static String get fmpApiKey => dotenv.env['FMP_API_KEY'] ?? '';
  static String get marketauxKey => dotenv.env['MARKETAUX_API_KEY'] ?? '';
  static String get alphaVantageKey => dotenv.env['ALPHAVANTAGE_API_KEY'] ?? '';
  static String get apiBaseUrl => dotenv.env['API_BASE_URL'] ?? '';

  static bool get isReady =>
      apiBaseUrl.isNotEmpty || (fmpApiKey.isNotEmpty && (marketauxKey.isNotEmpty || newsApiKey.isNotEmpty));

  static List<String> missingKeys() {
    if (apiBaseUrl.isNotEmpty) return [];
    final missing = <String>[];
    if (fmpApiKey.isEmpty) {
      missing.add('FMP_API_KEY');
    }
    if (marketauxKey.isEmpty && newsApiKey.isEmpty) {
      missing.add('MARKETAUX_API_KEY or NEWSAPI_KEY');
    }
    return missing;
  }
}

enum DataProvider { alphaVantage, financialModelingPrep }

class ApiService {
  static const String _newsBase = 'https://newsapi.org/v2';
  static const String _marketauxBase = 'https://api.marketaux.com/v1/news/all';
  static const String _alphaBase = 'https://www.alphavantage.co/query';
  static const String _fmpStableBase = 'https://financialmodelingprep.com/stable';
  static const String _fmpV3Base = 'https://financialmodelingprep.com/api/v3';
  static const DataProvider _provider = DataProvider.financialModelingPrep;
  static String get _proxyBase => AppSecrets.apiBaseUrl;
  static bool get _useProxy => _proxyBase.isNotEmpty;
  static List<QuoteItem> _quoteCache = [];
  static DateTime? _quoteCacheTime;
  static List<CompanySearchItem> _listingCache = [];
  static DateTime? _listingCacheTime;
  static final Map<String, List<double>> _historyCache = {};
  static final Map<String, DateTime> _historyCacheTime = {};
  static final Map<String, List<double>> _intradayCache = {};
  static final Map<String, DateTime> _intradayCacheTime = {};

  void _throwIfAlphaError(Map<String, dynamic> data) {
    final String? note = data['Note']?.toString();
    final String? error = data['Error Message']?.toString();
    final String? info = data['Information']?.toString();
    if (note != null && note.isNotEmpty) {
      throw Exception(note);
    }
    if (error != null && error.isNotEmpty) {
      throw Exception(error);
    }
    if (info != null && info.isNotEmpty) {
      throw Exception(info);
    }
  }

  Map<String, String> _fmpHeaders() {
    if (AppSecrets.fmpApiKey.isEmpty) return {};
    return {
      'apikey': AppSecrets.fmpApiKey,
      'x-api-key': AppSecrets.fmpApiKey,
    };
  }

  Future<List<NewsArticle>> fetchTopNews() async {
    final int page = _newsPageSeed();
    if (_useProxy) {
      final uri = Uri.parse('$_proxyBase/news/world').replace(queryParameters: {'page': '$page'});
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('Proxy news error: ${response.statusCode}');
      }
      final Map<String, dynamic> data = jsonDecode(response.body);
      final List<dynamic> articles = data['data'] as List<dynamic>? ?? [];
      return _dedupeArticles(articles.map((item) => NewsArticle.fromMarketaux(item)).toList());
    }
    if (AppSecrets.marketauxKey.isNotEmpty) {
      final uri = Uri.parse(_marketauxBase).replace(queryParameters: {
        'api_token': AppSecrets.marketauxKey,
        'language': 'en',
        'limit': '100',
        'page': '$page',
        'filter_entities': 'true',
        'categories': 'business,finance',
      });
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('Marketaux error: ${response.statusCode}');
      }
      final Map<String, dynamic> data = jsonDecode(response.body);
      final List<dynamic> articles = data['data'] as List<dynamic>? ?? [];
      return _dedupeArticles(articles.map((item) => NewsArticle.fromMarketaux(item)).toList());
    }
    final uri = Uri.parse('$_newsBase/top-headlines').replace(queryParameters: {
      'category': 'business',
      'q': 'business OR finance OR markets OR economy',
      'language': 'en',
      'pageSize': '40',
      'page': '$page',
      'apiKey': AppSecrets.newsApiKey,
    });
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('NewsAPI error: ${response.statusCode}');
    }
    final Map<String, dynamic> data = jsonDecode(response.body);
    if (data['status'] != 'ok') {
      throw Exception(data['message']?.toString() ?? 'NewsAPI error');
    }
    final List<dynamic> articles = data['articles'] as List<dynamic>;
    return _dedupeArticles(articles.map((item) => NewsArticle.fromNewsApi(item)).toList());
  }

  Future<List<NewsArticle>> fetchCompanyNews() async {
    if (_useProxy) {
      final uri = Uri.parse('$_proxyBase/news/company');
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('Proxy company news error: ${response.statusCode}');
      }
      final Map<String, dynamic> data = jsonDecode(response.body);
      final List<dynamic> articles = data['data'] as List<dynamic>? ?? [];
      return _dedupeArticles(articles.map((item) => NewsArticle.fromMarketaux(item)).toList());
    }
    if (_provider == DataProvider.financialModelingPrep) {
      final tickers =
          'AAPL,MSFT,TSLA,NVDA,BLK,AMZN,META,GOOGL,BRK.A,BRK.B,JPM,V,MA,TSM,ORCL,IBM,INTC,AMD,BABA,AVGO,ADBE,CRM,CSCO,NFLX,PEP,KO,DIS,NKE,ABNB';
      final List<Uri> candidates = [
        Uri.parse('$_fmpStableBase/stock-news').replace(queryParameters: {
          'tickers': tickers,
          'limit': '100',
          'apikey': AppSecrets.fmpApiKey,
        }),
        Uri.parse('$_fmpStableBase/stock_news').replace(queryParameters: {
          'tickers': tickers,
          'limit': '100',
          'apikey': AppSecrets.fmpApiKey,
        }),
        Uri.parse('$_fmpV3Base/stock_news').replace(queryParameters: {
          'tickers': tickers,
          'limit': '100',
          'apikey': AppSecrets.fmpApiKey,
        }),
      ];
      for (final uri in candidates) {
        final response = await http.get(uri, headers: _fmpHeaders());
        if (response.statusCode != 200) {
          continue;
        }
        final dynamic decoded = jsonDecode(response.body);
        if (decoded is List) {
          final List<dynamic> data = decoded;
          if (data.isNotEmpty) {
            return _dedupeArticles(data.map((item) => NewsArticle.fromFmp(item)).toList());
          }
        }
      }
      throw Exception('FMP news error: no data');
    }

    final int page = _newsPageSeed(offset: 3);
    final uri = Uri.parse('$_newsBase/everything').replace(queryParameters: {
      'q': '(AAPL OR Apple OR MSFT OR Microsoft OR TSLA OR Tesla OR NVDA OR NVIDIA OR BLK OR BlackRock OR earnings OR guidance OR revenue)',
      'language': 'en',
      'pageSize': '40',
      'page': '$page',
      'sortBy': 'publishedAt',
      'apiKey': AppSecrets.newsApiKey,
    });
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('NewsAPI error: ${response.statusCode}');
    }
    final Map<String, dynamic> data = jsonDecode(response.body);
    if (data['status'] != 'ok') {
      throw Exception(data['message']?.toString() ?? 'NewsAPI error');
    }
    final List<dynamic> articles = data['articles'] as List<dynamic>;
    return _dedupeArticles(articles.map((item) => NewsArticle.fromNewsApi(item)).toList());
  }

  Future<List<QuoteItem>> fetchQuotes(List<String> symbols) async {
    if (symbols.isEmpty) return [];
    if (_useProxy) {
      final uri = Uri.parse('$_proxyBase/market/quote').replace(queryParameters: {
        'symbols': symbols.join(','),
      });
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('Proxy quote error: ${response.statusCode}');
      }
      final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
      final quotes = data.map((item) => QuoteItem.fromFmp(item)).toList();
      _quoteCache = quotes;
      _quoteCacheTime = DateTime.now();
      return quotes;
    }
    if (_provider == DataProvider.financialModelingPrep) {
      final joined = symbols.join(',');
      final uri = Uri.parse('$_fmpStableBase/quote').replace(queryParameters: {
        'symbol': joined,
        'apikey': AppSecrets.fmpApiKey,
      });
      final response = await http.get(uri, headers: _fmpHeaders());
      if (response.statusCode == 200) {
        final dynamic decoded = jsonDecode(response.body);
        if (decoded is List && decoded.isNotEmpty) {
          final quotes = decoded.map((item) => QuoteItem.fromFmp(item)).toList();
          _quoteCache = quotes;
          _quoteCacheTime = DateTime.now();
          return quotes;
        }
      }
      final uriV3 = Uri.parse('$_fmpV3Base/quote/$joined').replace(queryParameters: {
        'apikey': AppSecrets.fmpApiKey,
      });
      final responseV3 = await http.get(uriV3, headers: _fmpHeaders());
      if (responseV3.statusCode != 200) {
        throw Exception('FMP quote error: ${responseV3.statusCode}');
      }
      final List<dynamic> dataV3 = jsonDecode(responseV3.body) as List<dynamic>;
      if (dataV3.isEmpty) {
        throw Exception('FMP returned no quotes.');
      }
      final quotes = dataV3.map((item) => QuoteItem.fromFmp(item)).toList();
      _quoteCache = quotes;
      _quoteCacheTime = DateTime.now();
      return quotes;
    }
    if (_quoteCache.isNotEmpty && _quoteCacheTime != null) {
      final age = DateTime.now().difference(_quoteCacheTime!);
      if (age.inMinutes < 5) {
        return _quoteCache;
      }
    }
    final Map<String, String> nameMap = {
      'AAPL': 'Apple Inc.',
      'MSFT': 'Microsoft Corporation',
      'TSLA': 'Tesla, Inc.',
      'NVDA': 'NVIDIA Corporation',
      'BLK': 'BlackRock, Inc.',
    };
    final List<QuoteItem> quotes = [];
    for (int index = 0; index < symbols.length; index++) {
      if (index > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 1200));
      }
      final symbol = symbols[index];
      try {
        final uri = Uri.parse(_alphaBase).replace(queryParameters: {
          'function': 'GLOBAL_QUOTE',
          'symbol': symbol,
          'apikey': AppSecrets.alphaVantageKey,
        });
        final response = await http.get(uri);
        if (response.statusCode != 200) {
          throw Exception('Alpha Vantage quote error: ${response.statusCode}');
        }
        final Map<String, dynamic> data = jsonDecode(response.body);
        _throwIfAlphaError(data);
        final Map<String, dynamic> quote = data['Global Quote'] as Map<String, dynamic>? ?? {};
        quotes.add(QuoteItem.fromAlphaQuote(quote, nameMap[symbol] ?? symbol));
      } catch (_) {
        // Skip failed symbols so rate limits don't block the entire view.
      }
    }
    if (quotes.isEmpty) {
      return _fallbackQuotes(nameMap);
    }
    _quoteCache = quotes;
    _quoteCacheTime = DateTime.now();
    return quotes;
  }

  List<QuoteItem> _fallbackQuotes(Map<String, String> nameMap) {
    return nameMap.entries
        .map((entry) => QuoteItem(
              symbol: entry.key,
              name: entry.value,
              price: 0,
              change: 0,
              changesPercentage: 0,
              volume: 0,
              isLive: false,
            ))
        .toList();
  }

  Future<List<CompanySearchItem>> searchCompanies(String query) async {
    if (_useProxy) {
      final uri = Uri.parse('$_proxyBase/market/search').replace(queryParameters: {
        'query': query,
      });
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('Proxy search error: ${response.statusCode}');
      }
      final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
      return data.map((item) => CompanySearchItem.fromFmp(item)).toList();
    }
    if (_provider == DataProvider.financialModelingPrep) {
      final uri = Uri.parse('$_fmpStableBase/search-name').replace(queryParameters: {
        'query': query,
        'apikey': AppSecrets.fmpApiKey,
      });
      final response = await http.get(uri, headers: _fmpHeaders());
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
        if (data.isNotEmpty) {
          return data.map((item) => CompanySearchItem.fromFmp(item)).toList();
        }
      }
      final uriV3 = Uri.parse('$_fmpV3Base/search').replace(queryParameters: {
        'query': query,
        'limit': '50',
        'apikey': AppSecrets.fmpApiKey,
      });
      final responseV3 = await http.get(uriV3, headers: _fmpHeaders());
      if (responseV3.statusCode != 200) {
        throw Exception('FMP search error: ${responseV3.statusCode}');
      }
      final List<dynamic> dataV3 = jsonDecode(responseV3.body) as List<dynamic>;
      return dataV3.map((item) => CompanySearchItem.fromFmp(item)).toList();
    }
    final uri = Uri.parse(_alphaBase).replace(queryParameters: {
      'function': 'SYMBOL_SEARCH',
      'keywords': query,
      'apikey': AppSecrets.alphaVantageKey,
    });
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Alpha Vantage search error: ${response.statusCode}');
    }
    final Map<String, dynamic> data = jsonDecode(response.body);
    _throwIfAlphaError(data);
    final List<dynamic> matches = data['bestMatches'] as List<dynamic>? ?? [];
    return matches.map((item) => CompanySearchItem.fromAlpha(item)).toList();
  }

  Future<Map<String, List<double>>> fetchHistoricalSeriesMap(List<String> symbols, {int points = 24}) async {
    final Map<String, List<double>> series = {};
    for (final symbol in symbols) {
      if (symbol.isEmpty) continue;
      final cached = _getHistoryFromCache(symbol);
      if (cached != null && cached.isNotEmpty) {
        series[symbol] = cached;
        continue;
      }
      try {
        final data = await fetchHistoricalSeries(symbol, points: points);
        if (data.isNotEmpty) {
          series[symbol] = data;
          _historyCache[symbol] = data;
          _historyCacheTime[symbol] = DateTime.now();
        }
      } catch (_) {
        // Ignore series failures so the dashboard can still render.
      }
      await Future<void>.delayed(const Duration(milliseconds: 140));
    }
    return series;
  }

  Future<Map<String, List<double>>> fetchIntradaySeriesMap(
    List<String> symbols, {
    int points = 24,
    String interval = '1hour',
  }) async {
    final Map<String, List<double>> series = {};
    for (final symbol in symbols) {
      if (symbol.isEmpty) continue;
      final cached = _getIntradayFromCache(symbol, interval);
      if (cached != null && cached.isNotEmpty) {
        series[symbol] = cached;
        continue;
      }
      try {
        final data = await fetchIntradaySeries(symbol, points: points, interval: interval);
        if (data.isNotEmpty) {
          series[symbol] = data;
          _intradayCache[_intradayKey(symbol, interval)] = data;
          _intradayCacheTime[_intradayKey(symbol, interval)] = DateTime.now();
        }
      } catch (_) {
        // Ignore series failures so the dashboard can still render.
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    return series;
  }

  List<double>? _getHistoryFromCache(String symbol) {
    final cached = _historyCache[symbol];
    final cachedAt = _historyCacheTime[symbol];
    if (cached == null || cachedAt == null) return null;
    final age = DateTime.now().difference(cachedAt);
    if (age.inMinutes > 30) {
      _historyCache.remove(symbol);
      _historyCacheTime.remove(symbol);
      return null;
    }
    return cached;
  }

  List<double>? _getIntradayFromCache(String symbol, String interval) {
    final key = _intradayKey(symbol, interval);
    final cached = _intradayCache[key];
    final cachedAt = _intradayCacheTime[key];
    if (cached == null || cachedAt == null) return null;
    final age = DateTime.now().difference(cachedAt);
    if (age.inMinutes > 10) {
      _intradayCache.remove(key);
      _intradayCacheTime.remove(key);
      return null;
    }
    return cached;
  }

  String _intradayKey(String symbol, String interval) => '${symbol}_$interval';

  Future<List<double>> fetchHistoricalSeries(String symbol, {int points = 24}) async {
    final DateTime now = DateTime.now();
    final DateTime fromDate = now.subtract(Duration(days: points * 3));
    final String from = _formatDate(fromDate);
    final String to = _formatDate(now);

    if (_useProxy) {
      final uri = Uri.parse('$_proxyBase/market/history').replace(queryParameters: {
        'symbol': symbol,
        'from': from,
        'to': to,
      });
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('Proxy history error: ${response.statusCode}');
      }
      final dynamic decoded = jsonDecode(response.body);
      return _extractSeries(decoded, points: points);
    }

    if (_provider == DataProvider.financialModelingPrep) {
      final lightUri = Uri.parse('$_fmpStableBase/historical-price-eod/light').replace(queryParameters: {
        'symbol': symbol,
        'from': from,
        'to': to,
        'apikey': AppSecrets.fmpApiKey,
      });
      final response = await http.get(lightUri, headers: _fmpHeaders());
      if (response.statusCode == 200) {
        final dynamic decoded = jsonDecode(response.body);
        final series = _extractSeries(decoded, points: points);
        if (series.isNotEmpty) return series;
      }

      final fullUri = Uri.parse('$_fmpStableBase/historical-price-eod/full').replace(queryParameters: {
        'symbol': symbol,
        'from': from,
        'to': to,
        'apikey': AppSecrets.fmpApiKey,
      });
      final responseFull = await http.get(fullUri, headers: _fmpHeaders());
      if (responseFull.statusCode != 200) {
        throw Exception('FMP history error: ${responseFull.statusCode}');
      }
      final dynamic decoded = jsonDecode(responseFull.body);
      return _extractSeries(decoded, points: points);
    }

    return [];
  }

  Future<List<double>> fetchIntradaySeries(
    String symbol, {
    int points = 24,
    String interval = '1hour',
  }) async {
    if (_useProxy) {
      final uri = Uri.parse('$_proxyBase/market/intraday').replace(queryParameters: {
        'symbol': symbol,
        'interval': interval,
      });
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('Proxy intraday error: ${response.statusCode}');
      }
      final dynamic decoded = jsonDecode(response.body);
      return _extractSeries(decoded, points: points);
    }

    if (_provider == DataProvider.financialModelingPrep) {
      final stableUri = Uri.parse('$_fmpStableBase/historical-chart/$interval').replace(queryParameters: {
        'symbol': symbol,
        'apikey': AppSecrets.fmpApiKey,
      });
      final response = await http.get(stableUri, headers: _fmpHeaders());
      if (response.statusCode == 200) {
        final dynamic decoded = jsonDecode(response.body);
        final series = _extractSeries(decoded, points: points);
        if (series.isNotEmpty) return series;
      }

      final v3Uri = Uri.parse('$_fmpV3Base/historical-chart/$interval/$symbol').replace(queryParameters: {
        'apikey': AppSecrets.fmpApiKey,
      });
      final responseV3 = await http.get(v3Uri, headers: _fmpHeaders());
      if (responseV3.statusCode != 200) {
        throw Exception('FMP intraday error: ${responseV3.statusCode}');
      }
      final dynamic decodedV3 = jsonDecode(responseV3.body);
      return _extractSeries(decodedV3, points: points);
    }

    return [];
  }

  List<double> _extractSeries(dynamic decoded, {required int points}) {
    if (decoded == null) return [];
    List<dynamic> raw;
    if (decoded is List) {
      raw = decoded;
    } else if (decoded is Map<String, dynamic> && decoded['historical'] is List) {
      raw = decoded['historical'] as List<dynamic>;
    } else {
      return [];
    }

    final entries = raw
        .map((item) => {
              'date': item['date']?.toString() ?? '',
              'close': _parseNum(item['close'] ?? item['adjClose']),
            })
        .where((item) => (item['date'] as String).isNotEmpty)
        .toList();

    entries.sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
    final values = entries.map((item) => item['close'] as double).where((value) => value > 0).toList();
    if (values.isEmpty) return [];
    final start = values.length > points ? values.length - points : 0;
    return values.sublist(start);
  }

  double _parseNum(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _formatDate(DateTime date) {
    return date.toIso8601String().split('T').first;
  }

  Future<List<CompanySearchItem>> fetchAllListings() async {
    if (_listingCache.isNotEmpty && _listingCacheTime != null) {
      final age = DateTime.now().difference(_listingCacheTime!);
      if (age.inHours < 24) {
        return _listingCache;
      }
    }
    if (_useProxy) {
      final uri = Uri.parse('$_proxyBase/market/listings');
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('Proxy listing error: ${response.statusCode}');
      }
      final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
      final listings = data
          .map((item) => CompanySearchItem.fromFmpListing(item))
          .where((item) => _isTargetExchange(item.exchange))
          .toList();
      _listingCache = listings;
      _listingCacheTime = DateTime.now();
      return listings;
    }
    if (_provider == DataProvider.financialModelingPrep) {
      final uri = Uri.parse('$_fmpStableBase/stock-list').replace(queryParameters: {
        'apikey': AppSecrets.fmpApiKey,
      });
      final response = await http.get(uri, headers: _fmpHeaders());
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
        if (data.isNotEmpty) {
          final listings = data
              .map((item) => CompanySearchItem.fromFmpListing(item))
              .where((item) => _isTargetExchange(item.exchange))
              .toList();
          _listingCache = listings;
          _listingCacheTime = DateTime.now();
          return listings;
        }
      }
      final uriV3 = Uri.parse('$_fmpV3Base/stock/list').replace(queryParameters: {
        'apikey': AppSecrets.fmpApiKey,
      });
      final responseV3 = await http.get(uriV3, headers: _fmpHeaders());
      if (responseV3.statusCode != 200) {
        throw Exception('FMP listing error: ${responseV3.statusCode}');
      }
      final List<dynamic> dataV3 = jsonDecode(responseV3.body) as List<dynamic>;
      final listings = dataV3
          .map((item) => CompanySearchItem.fromFmpListing(item))
          .where((item) => _isTargetExchange(item.exchange))
          .toList();
      _listingCache = listings;
      _listingCacheTime = DateTime.now();
      return listings;
    }
    final uri = Uri.parse(_alphaBase).replace(queryParameters: {
      'function': 'LISTING_STATUS',
      'state': 'active',
      'apikey': AppSecrets.alphaVantageKey,
    });
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Alpha Vantage listing error: ${response.statusCode}');
    }
    final String body = response.body;
    final List<CompanySearchItem> listings = _parseListingsCsv(body);
    _listingCache = listings;
    _listingCacheTime = DateTime.now();
    return listings;
  }

  List<CompanySearchItem> _parseListingsCsv(String csv) {
    final lines = csv.split('\n');
    if (lines.length <= 1) return [];
    final List<CompanySearchItem> results = [];
    for (int i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final fields = _parseCsvLine(line);
      if (fields.length < 3) continue;
      final symbol = fields[0];
      final name = fields[1];
      final exchange = fields[2];
      if (!_isTargetExchange(exchange)) continue;
      results.add(CompanySearchItem.fromListing(symbol, name, exchange));
    }
    return results;
  }

  List<String> _parseCsvLine(String line) {
    final List<String> fields = [];
    final StringBuffer buffer = StringBuffer();
    bool inQuotes = false;
    for (int i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        inQuotes = !inQuotes;
        continue;
      }
      if (char == ',' && !inQuotes) {
        fields.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    fields.add(buffer.toString());
    return fields.map((value) => value.trim()).toList();
  }

  bool _isTargetExchange(String exchange) {
    final upper = exchange.toUpperCase();
    return upper.contains('NYSE') || upper.contains('LSE') || upper.contains('LONDON');
  }

  Future<CompanyProfile?> fetchCompanyProfile(String symbol) async {
    if (_useProxy) {
      final uri = Uri.parse('$_proxyBase/market/profile').replace(queryParameters: {
        'symbol': symbol,
      });
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('Proxy profile error: ${response.statusCode}');
      }
      final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
      if (data.isEmpty) return null;
      return CompanyProfile.fromFmp(data.first);
    }
    if (_provider == DataProvider.financialModelingPrep) {
      final uri = Uri.parse('$_fmpStableBase/profile').replace(queryParameters: {
        'symbol': symbol,
        'apikey': AppSecrets.fmpApiKey,
      });
      final response = await http.get(uri, headers: _fmpHeaders());
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
        if (data.isNotEmpty) return CompanyProfile.fromFmp(data.first);
      }
      final uriV3 = Uri.parse('$_fmpV3Base/profile/$symbol').replace(queryParameters: {
        'apikey': AppSecrets.fmpApiKey,
      });
      final responseV3 = await http.get(uriV3, headers: _fmpHeaders());
      if (responseV3.statusCode != 200) {
        throw Exception('FMP profile error: ${responseV3.statusCode}');
      }
      final List<dynamic> dataV3 = jsonDecode(responseV3.body) as List<dynamic>;
      if (dataV3.isEmpty) return null;
      return CompanyProfile.fromFmp(dataV3.first);
    }
    final uri = Uri.parse(_alphaBase).replace(queryParameters: {
      'function': 'OVERVIEW',
      'symbol': symbol,
      'apikey': AppSecrets.alphaVantageKey,
    });
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Alpha Vantage overview error: ${response.statusCode}');
    }
    final Map<String, dynamic> data = jsonDecode(response.body);
    _throwIfAlphaError(data);
    if (data.isEmpty || data['Name'] == null) return null;
    return CompanyProfile.fromAlpha(data);
  }

  Future<CompanyQuote?> fetchQuote(String symbol) async {
    if (_useProxy) {
      final uri = Uri.parse('$_proxyBase/market/quote').replace(queryParameters: {
        'symbol': symbol,
      });
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('Proxy quote error: ${response.statusCode}');
      }
      final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
      if (data.isEmpty) return null;
      return CompanyQuote.fromFmp(data.first);
    }
    if (_provider == DataProvider.financialModelingPrep) {
      final uri = Uri.parse('$_fmpStableBase/quote').replace(queryParameters: {
        'symbol': symbol,
        'apikey': AppSecrets.fmpApiKey,
      });
      final response = await http.get(uri, headers: _fmpHeaders());
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
        if (data.isNotEmpty) return CompanyQuote.fromFmp(data.first);
      }
      final uriV3 = Uri.parse('$_fmpV3Base/quote/$symbol').replace(queryParameters: {
        'apikey': AppSecrets.fmpApiKey,
      });
      final responseV3 = await http.get(uriV3, headers: _fmpHeaders());
      if (responseV3.statusCode != 200) {
        throw Exception('FMP quote error: ${responseV3.statusCode}');
      }
      final List<dynamic> dataV3 = jsonDecode(responseV3.body) as List<dynamic>;
      if (dataV3.isEmpty) return null;
      return CompanyQuote.fromFmp(dataV3.first);
    }
    final uri = Uri.parse(_alphaBase).replace(queryParameters: {
      'function': 'GLOBAL_QUOTE',
      'symbol': symbol,
      'apikey': AppSecrets.alphaVantageKey,
    });
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Alpha Vantage quote error: ${response.statusCode}');
    }
    final Map<String, dynamic> data = jsonDecode(response.body);
    _throwIfAlphaError(data);
    final Map<String, dynamic> quote = data['Global Quote'] as Map<String, dynamic>? ?? {};
    if (quote.isEmpty) return null;
    return CompanyQuote.fromAlpha(quote);
  }

  int _newsPageSeed({int offset = 0}) {
    final seed = DateTime.now().millisecondsSinceEpoch ~/ 60000;
    return (seed + offset) % 3 + 1;
  }

  List<NewsArticle> _dedupeArticles(List<NewsArticle> articles) {
    final seen = <String>{};
    final List<NewsArticle> results = [];
    for (final article in articles) {
      final keySource = [
        article.url,
        article.title,
        article.publishedAt,
        article.source,
      ].where((part) => part.isNotEmpty).join('|');
      final key = keySource.toLowerCase();
      if (key.isEmpty || seen.contains(key)) {
        continue;
      }
      seen.add(key);
      results.add(article);
    }
    return results;
  }
}
