import 'dart:ui';

import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/gestures.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  runApp(const AppMineApp());
}

class AppMineApp extends StatelessWidget {
  const AppMineApp({super.key});

  ThemeData _buildTheme(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;
    final Color base = isDark ? const Color(0xFF0B1222) : const Color(0xFFF4F8FF);
    final Color surface = isDark ? const Color(0xFF151F36) : const Color(0xFFE7F1FF);
    final Color primary = isDark ? const Color(0xFFA6C9E6) : const Color(0xFF5AA6E8);
    final Color textColor = isDark ? const Color(0xFFEAF2FF) : const Color(0xFF0B1A2B);

    return ThemeData(
      brightness: brightness,
      useMaterial3: true,
      scaffoldBackgroundColor: base,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: primary,
        onPrimary: isDark ? const Color(0xFF0B1222) : Colors.white,
        secondary: isDark ? const Color(0xFF7FA7C7) : const Color(0xFF7CB6EA),
        onSecondary: isDark ? const Color(0xFF0B1222) : Colors.white,
        error: const Color(0xFFE66B6B),
        onError: Colors.white,
        surface: surface,
        onSurface: textColor,
      ),
      textTheme: GoogleFonts.manropeTextTheme().apply(
        bodyColor: textColor,
        displayColor: textColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'APPMINE',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      scrollBehavior: const AppScrollBehavior(),
      home: const SplashScreen(),
    );
  }
}

class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

class AppSecrets {
  static String get newsApiKey => dotenv.env['NEWSAPI_KEY'] ?? '';
  static String get fmpApiKey => dotenv.env['FMP_API_KEY'] ?? '';
  static String get marketauxKey => dotenv.env['MARKETAUX_API_KEY'] ?? '';
  static String get alphaVantageKey => dotenv.env['ALPHAVANTAGE_API_KEY'] ?? '';
  static String get apiBaseUrl => dotenv.env['API_BASE_URL'] ?? '';

  static bool get isReady =>
      apiBaseUrl.isNotEmpty || (fmpApiKey.isNotEmpty && (marketauxKey.isNotEmpty || newsApiKey.isNotEmpty));
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

  Future<List<CalendarEvent>> fetchEconomicCalendar({required String from, required String to}) async {
    if (_useProxy) {
      final uri = Uri.parse('$_proxyBase/calendar/economic').replace(queryParameters: {'from': from, 'to': to});
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('Proxy economic calendar error: ${response.statusCode}');
      }
      final dynamic data = jsonDecode(response.body);
      return _parseCalendarEvents(data, type: CalendarEventType.economic);
    }
    final uri = Uri.parse('$_fmpStableBase/economic-calendar').replace(queryParameters: {
      'from': from,
      'to': to,
      'apikey': AppSecrets.fmpApiKey,
    });
    final response = await http.get(uri, headers: _fmpHeaders());
    if (response.statusCode != 200) {
      throw Exception('FMP economic calendar error: ${response.statusCode}');
    }
    final dynamic data = jsonDecode(response.body);
    return _parseCalendarEvents(data, type: CalendarEventType.economic);
  }

  Future<List<CalendarEvent>> fetchEarningsCalendar({required String from, required String to}) async {
    if (_useProxy) {
      final uri = Uri.parse('$_proxyBase/calendar/earnings').replace(queryParameters: {'from': from, 'to': to});
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('Proxy earnings calendar error: ${response.statusCode}');
      }
      final dynamic data = jsonDecode(response.body);
      return _parseCalendarEvents(data, type: CalendarEventType.earnings);
    }
    final uri = Uri.parse('$_fmpStableBase/earnings-calendar').replace(queryParameters: {
      'from': from,
      'to': to,
      'apikey': AppSecrets.fmpApiKey,
    });
    final response = await http.get(uri, headers: _fmpHeaders());
    if (response.statusCode != 200) {
      throw Exception('FMP earnings calendar error: ${response.statusCode}');
    }
    final dynamic data = jsonDecode(response.body);
    return _parseCalendarEvents(data, type: CalendarEventType.earnings);
  }

  Future<List<CalendarEvent>> fetchUpcomingEvents() async {
    final now = DateTime.now();
    final from = _formatDate(now.subtract(const Duration(days: 1)));
    final to = _formatDate(now.add(const Duration(days: 21)));
    final results = await Future.wait([
      fetchEconomicCalendar(from: from, to: to),
      fetchEarningsCalendar(from: from, to: to),
    ]);
    final combined = [...results[0], ...results[1]];
    combined.sort((a, b) => a.date.compareTo(b.date));
    return combined.take(10).toList();
  }

  Future<List<HistoricalPoint>> fetchHistoricalSeries({
    required String symbol,
    required String from,
    required String to,
  }) async {
    if (_useProxy) {
      final uri = Uri.parse('$_proxyBase/market/history')
          .replace(queryParameters: {'symbol': symbol, 'from': from, 'to': to});
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('Proxy history error: ${response.statusCode}');
      }
      final dynamic data = jsonDecode(response.body);
      return _parseHistory(data);
    }
    final uri = Uri.parse('$_fmpStableBase/historical-price-eod/light').replace(queryParameters: {
      'symbol': symbol,
      'from': from,
      'to': to,
      'apikey': AppSecrets.fmpApiKey,
    });
    final response = await http.get(uri, headers: _fmpHeaders());
    if (response.statusCode != 200) {
      throw Exception('FMP history error: ${response.statusCode}');
    }
    final dynamic data = jsonDecode(response.body);
    return _parseHistory(data);
  }

  List<CalendarEvent> _parseCalendarEvents(dynamic data, {required CalendarEventType type}) {
    final List<dynamic> list = data is List ? data : (data is Map ? (data['data'] as List<dynamic>? ?? []) : []);
    return list.map((raw) => CalendarEvent.fromMap(raw as Map<String, dynamic>, type: type)).toList();
  }

  List<HistoricalPoint> _parseHistory(dynamic data) {
    List<dynamic> list = [];
    if (data is List) {
      list = data;
    } else if (data is Map && data['historical'] is List) {
      list = data['historical'] as List<dynamic>;
    }
    final points = <HistoricalPoint>[];
    for (final item in list) {
      if (item is! Map) continue;
      final dateRaw = item['date']?.toString() ?? '';
      final closeRaw = item['close'] ?? item['adjClose'] ?? item['price'];
      final date = DateTime.tryParse(dateRaw);
      final close = closeRaw is num ? closeRaw.toDouble() : double.tryParse(closeRaw?.toString() ?? '');
      if (date == null || close == null) continue;
      points.add(HistoricalPoint(date: date, value: close));
    }
    if (points.isEmpty) return [];
    points.sort((a, b) => a.date.compareTo(b.date));
    final Map<int, HistoricalPoint> byYear = {};
    for (final point in points) {
      byYear[point.date.year] = point;
    }
    final yearly = byYear.values.toList()..sort((a, b) => a.date.compareTo(b.date));
    return yearly;
  }

  String _formatDate(DateTime date) {
    final String mm = date.month.toString().padLeft(2, '0');
    final String dd = date.day.toString().padLeft(2, '0');
    return '${date.year}-$mm-$dd';
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

  Future<List<PeerCompany>> fetchPeerCompanies(String sector) async {
    if (sector.isEmpty) return [];
    if (_useProxy) {
      final uri = Uri.parse('$_proxyBase/market/peers').replace(queryParameters: {'sector': sector});
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('Proxy peers error: ${response.statusCode}');
      }
      final dynamic data = jsonDecode(response.body);
      if (data is List) {
        return data.map((item) => PeerCompany.fromFmp(item)).toList();
      }
      return [];
    }
    final uri = Uri.parse('$_fmpStableBase/stock-screener').replace(queryParameters: {
      'sector': sector,
      'limit': '20',
      'apikey': AppSecrets.fmpApiKey,
    });
    final response = await http.get(uri, headers: _fmpHeaders());
    if (response.statusCode != 200) {
      throw Exception('FMP peers error: ${response.statusCode}');
    }
    final dynamic data = jsonDecode(response.body);
    if (data is List) {
      return data.map((item) => PeerCompany.fromFmp(item)).toList();
    }
    return [];
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

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  void _openDashboard(BuildContext context) {
    Navigator.of(context).pushReplacement(AppNavigation.routeTo(const DashboardScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return AppBackdrop(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LogoButton(
              size: 180,
              onTap: () => _openDashboard(context),
            ),
            if (!AppSecrets.isReady) ...[
              const SizedBox(height: 24),
              GlassPanel(
                child: Text(
                  'API keys missing. Add NEWSAPI_KEY and FMP_API_KEY to .env.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final ApiService _api = ApiService();
  late Future<DashboardData> _dataFuture;
  static const List<String> _featuredSymbols = ['AAPL', 'MSFT', 'TSLA', 'NVDA', 'BLK'];
  static const List<MarketTickerSpec> _macroSpecs = [
    MarketTickerSpec(label: 'NASDAQ', symbol: '^IXIC'),
    MarketTickerSpec(label: 'Bitcoin', symbol: 'BTCUSD'),
    MarketTickerSpec(label: 'EU 50', symbol: '^STOXX50E'),
    MarketTickerSpec(label: 'VIX', symbol: '^VIX'),
    MarketTickerSpec(label: 'Japan 225', symbol: '^N225'),
    MarketTickerSpec(label: 'USA 30', symbol: '^DJI'),
    MarketTickerSpec(label: 'UK 100', symbol: '^FTSE'),
    MarketTickerSpec(label: 'GBP/USD', symbol: 'GBPUSD'),
    MarketTickerSpec(label: 'EUR/USD', symbol: 'EURUSD'),
    MarketTickerSpec(label: 'USA 500', symbol: '^GSPC'),
    MarketTickerSpec(label: 'Crude Oil', symbol: 'CLUSD'),
    MarketTickerSpec(label: 'USA Tech 100', symbol: '^NDX'),
    MarketTickerSpec(label: 'Silver', symbol: 'XAGUSD'),
    MarketTickerSpec(label: 'Gold', symbol: 'XAUUSD'),
    MarketTickerSpec(label: 'Natural Gas', symbol: 'NGUSD'),
  ];
  final List<ChecklistItemData> _checklist = [
    ChecklistItemData(label: 'Review revenue growth', detail: 'Compare YoY and QoQ trends'),
    ChecklistItemData(label: 'Check profit margins', detail: 'Gross + operating margin shifts'),
    ChecklistItemData(label: 'Scan cash flow', detail: 'Free cash flow consistency'),
    ChecklistItemData(label: 'Compare valuation', detail: 'P/E vs sector median'),
    ChecklistItemData(label: 'Read latest earnings', detail: 'Guidance + call highlights'),
  ];

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
  }

  Future<DashboardData> _loadData() async {
    if (!AppSecrets.isReady) {
      throw Exception('Missing API keys');
    }
    final featuredFuture = _api.fetchQuotes(_featuredSymbols);
    final macroFuture = _api.fetchQuotes(_macroSpecs.map((e) => e.symbol).toList());
    final eventsFuture = _api.fetchUpcomingEvents();
    final historyFuture = _api.fetchHistoricalSeries(
      symbol: '^IXIC',
      from: '1971-01-01',
      to: _formatDate(DateTime.now()),
    );
    final featured = await featuredFuture;
    List<QuoteItem> macro = [];
    List<CalendarEvent> events = [];
    List<HistoricalPoint> history = [];
    try {
      macro = await macroFuture;
    } catch (_) {
      macro = [];
    }
    try {
      events = await eventsFuture;
    } catch (_) {
      events = [];
    }
    try {
      history = await historyFuture;
    } catch (_) {
      history = [];
    }
    List<NewsArticle> news = [];
    try {
      news = await _api.fetchTopNews();
    } catch (_) {
      news = [];
    }
    return DashboardData(featured: featured, news: news, macro: macro, events: events, history: history);
  }

  @override
  Widget build(BuildContext context) {
    return AppBackdrop(
      child: ResponsiveScaffold(
        selected: 0,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TopBar(
                title: 'Dashboard',
                onSearch: (value) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CompaniesScreen(initialQuery: value),
                    ),
                  );
                },
                onAction: () {},
              ),
              const SizedBox(height: 24),
              Expanded(
                  child: FutureBuilder<DashboardData>(
                    future: _dataFuture,
                    builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: GlassPanel(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Unable to load market data.', style: Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: 8),
                              Text(
                                _errorMessage(snapshot.error),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 12),
                              GlassPill(
                                label: 'Retry',
                                selected: true,
                                onTap: () {
                                  setState(() => _dataFuture = _loadData());
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    final data = snapshot.data!;
                    final summary = _buildMarketSummary(data.featured);
                    final newsPreview = data.news.take(2).toList();
                    final macroMap = {
                      for (final item in data.macro) item.symbol.toUpperCase(): item,
                    };
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final double width = constraints.maxWidth;
                        final int columns = width >= 1300 ? 3 : (width >= 900 ? 2 : 1);
                        final double aspect = columns == 3 ? 1.45 : (columns == 2 ? 1.3 : 1.15);
                        return GridView.count(
                          crossAxisCount: columns,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          childAspectRatio: aspect,
                          physics: const BouncingScrollPhysics(),
                          cacheExtent: 800,
                          children: [
                            DashboardPanel(
                              title: 'Quick Actions',
                              child: QuickActionsPanel(
                                featured: data.featured,
                                summary: summary,
                                news: newsPreview,
                                onNews: () => AppNavigation.go(context, 1),
                                onCompanies: () => AppNavigation.go(context, 2),
                                onSaved: () => AppNavigation.go(context, 3),
                              ),
                            ),
                            DashboardPanel(
                              title: 'Checklist',
                              child: ChecklistPanel(
                                items: _checklist,
                                onToggle: (index, value) {
                                  setState(() {
                                    _checklist[index] = _checklist[index].copyWith(done: value);
                                  });
                                },
                              ),
                            ),
                            DashboardPanel(
                              title: 'Watchlist Preview',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (data.featured.isNotEmpty) MiniWatchRow(item: data.featured[0]),
                                  if (data.featured.length > 1) MiniWatchRow(item: data.featured[1]),
                                  if (data.featured.length > 2) MiniWatchRow(item: data.featured[2]),
                                  if (data.featured.length > 3) MiniWatchRow(item: data.featured[3]),
                                ],
                              ),
                            ),
                            DashboardPanel(
                              title: 'Global Markets',
                              child: Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: _macroSpecs.map((spec) {
                                  final QuoteItem? item = macroMap[spec.symbol.toUpperCase()];
                                  return MarketChip(spec: spec, item: item);
                                }).toList(),
                              ),
                            ),
                            DashboardPanel(
                              title: 'Upcoming Events',
                              child: UpcomingEventsPanel(events: data.events),
                            ),
                            DashboardPanel(
                              title: 'Long-term Trend',
                              child: TrendPanel(points: data.history),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _errorMessage(Object? error) {
    if (error == null) return 'Unknown error.';
    final String message = error.toString();
    return message.replaceAll('Exception: ', '');
  }

  String _formatDate(DateTime date) {
    final String mm = date.month.toString().padLeft(2, '0');
    final String dd = date.day.toString().padLeft(2, '0');
    return '${date.year}-$mm-$dd';
  }

  MarketSummary _buildMarketSummary(List<QuoteItem> items) {
    if (items.isEmpty) {
      return MarketSummary.empty();
    }
    final sorted = [...items]..sort((a, b) => b.changesPercentage.compareTo(a.changesPercentage));
    final top = sorted.first;
    final bottom = sorted.last;
    final secondary = sorted.length > 2 ? sorted[1] : null;
    final avg = items.map((e) => e.changesPercentage).reduce((a, b) => a + b) / items.length;
    final advancers = items.where((e) => e.changesPercentage >= 0).length;
    final decliners = items.length - advancers;
    return MarketSummary(
      avgChange: '${avg.toStringAsFixed(2)}%',
      advancers: advancers,
      decliners: decliners,
      topMover: top,
      bottomMover: bottom,
      secondaryMover: secondary,
    );
  }
}

class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  final ApiService _api = ApiService();
  late Future<List<NewsArticle>> _newsFuture;
  bool _showCompanyNews = false;

  @override
  void initState() {
    super.initState();
    _newsFuture = _loadNews();
  }

  Future<List<NewsArticle>> _loadNews() {
    return _showCompanyNews ? _api.fetchCompanyNews() : _api.fetchTopNews();
  }

  void _toggleNews(bool company) {
    setState(() {
      _showCompanyNews = company;
      _newsFuture = _loadNews();
    });
  }

  void _openArticle(BuildContext context, NewsArticle article) {
    showDialog<void>(
      context: context,
      builder: (_) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: GlassPanel(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(article.title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text('${article.source} · ${article.publishedAt}', style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 12),
                    if (article.imageUrl.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(article.imageUrl, height: 220, width: double.infinity, fit: BoxFit.cover),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      article.content.isNotEmpty ? article.content : article.description,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (article.url.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: () => _launchArticle(article.url),
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Open full article'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _launchArticle(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return AppBackdrop(
      child: ResponsiveScaffold(
        selected: 1,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TopBar(
                title: 'News',
                onSearch: (value) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CompaniesScreen(initialQuery: value),
                    ),
                  );
                },
                onAction: () {},
              ),
              const SizedBox(height: 20),
              Text('Financial News', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                'Stay up to date with the latest market news.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurface.withOpacity(0.7)),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  GlassPill(
                    label: 'World & Finance',
                    selected: !_showCompanyNews,
                    onTap: () => _toggleNews(false),
                  ),
                  const SizedBox(width: 12),
                  GlassPill(
                    label: 'Company News',
                    selected: _showCompanyNews,
                    onTap: () => _toggleNews(true),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Expanded(
                child: FutureBuilder<List<NewsArticle>>(
                  future: _newsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: GlassPanel(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Unable to load news.', style: Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: 8),
                              Text(_errorMessage(snapshot.error), style: Theme.of(context).textTheme.bodySmall),
                              const SizedBox(height: 12),
                              GlassPill(
                                label: 'Retry',
                                selected: true,
                                onTap: () {
                                  setState(() => _newsFuture = _loadNews());
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    final news = snapshot.data ?? [];
                    final bool isWide = MediaQuery.sizeOf(context).width >= 1100;
                    return GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: isWide ? 3 : 1,
                        mainAxisSpacing: 18,
                        crossAxisSpacing: 18,
                        childAspectRatio: isWide ? 1.05 : 0.9,
                      ),
                      physics: const BouncingScrollPhysics(),
                      cacheExtent: 800,
                      itemCount: news.length,
                      itemBuilder: (context, index) {
                        final article = news[index];
                        return NewsCard(
                          category: article.source,
                          title: article.title,
                          summary: article.description,
                          date: article.publishedAt,
                          imageUrl: article.imageUrl,
                          onOpen: () => _launchArticle(article.url),
                          onDetails: () => _openArticle(context, article),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _errorMessage(Object? error) {
    if (error == null) return 'Unknown error.';
    final String message = error.toString();
    return message.replaceAll('Exception: ', '');
  }
}

class CompaniesScreen extends StatefulWidget {
  const CompaniesScreen({super.key, this.initialQuery});

  final String? initialQuery;

  @override
  State<CompaniesScreen> createState() => _CompaniesScreenState();
}

class _CompaniesScreenState extends State<CompaniesScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _controller = TextEditingController();
  List<CompanySearchItem> _results = [];
  List<CompanySearchItem> _nyseListings = [];
  bool _loading = false;
  String _error = '';
  int _pageIndex = 0;
  static const int _pageSize = 50;
  late Future<List<QuoteItem>> _featuredFuture;
  static const List<String> _featuredSymbols = ['AAPL', 'MSFT', 'TSLA', 'NVDA', 'BLK'];

  @override
  void initState() {
    super.initState();
    _featuredFuture = _api.fetchQuotes(_featuredSymbols);
    if (widget.initialQuery != null && widget.initialQuery!.trim().isNotEmpty) {
      _controller.text = widget.initialQuery!.trim();
      _search(widget.initialQuery!.trim());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final String q = query.trim().toLowerCase();
      final listings = await _api.fetchAllListings();
      final localMatches = listings.where((item) {
        return item.symbol.toLowerCase().contains(q) || item.name.toLowerCase().contains(q);
      }).take(50).toList();
      if (localMatches.isNotEmpty) {
        setState(() {
          _results = localMatches;
        });
      } else {
        final items = await _api.searchCompanies(query.trim());
        final filtered = items.where((item) {
          final ex = item.exchange.toUpperCase();
          return ex.contains('NYSE') || ex.contains('LSE') || ex.contains('LONDON');
        }).toList();
        setState(() {
          _results = filtered.isNotEmpty ? filtered : items;
        });
      }
    } catch (err) {
      setState(() {
        _error = 'Search failed. Try again.';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _loadNyseDirectory() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final listings = await _api.fetchAllListings();
      final nyse = listings.where((item) => item.exchange.toUpperCase().contains('NYSE')).toList();
      setState(() {
        _nyseListings = nyse;
        _pageIndex = 0;
      });
    } catch (err) {
      setState(() {
        _error = 'Directory load failed. Try again.';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  List<CompanySearchItem> get _pagedNyse {
    if (_nyseListings.isEmpty) return [];
    final start = _pageIndex * _pageSize;
    final end = (start + _pageSize).clamp(0, _nyseListings.length);
    return _nyseListings.sublist(start, end);
  }

  @override
  Widget build(BuildContext context) {
    return AppBackdrop(
      child: ResponsiveScaffold(
        selected: 2,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TopBar(
                title: 'Companies',
                onSearch: (value) => _search(value),
                onAction: () {},
              ),
              const SizedBox(height: 18),
              GlassPanel(
                child: TextField(
                  controller: _controller,
                  onSubmitted: _search,
                  decoration: const InputDecoration(
                    hintText: 'Search any NYSE or LSE company...',
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  GlassPill(
                    label: 'Browse NYSE Directory',
                    selected: _nyseListings.isNotEmpty,
                    onTap: _loadNyseDirectory,
                  ),
                  const SizedBox(width: 12),
                  if (_nyseListings.isNotEmpty)
                    Text(
                      'Page ${_pageIndex + 1} of ${( (_nyseListings.length / _pageSize).ceil()).clamp(1, 999)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
              const SizedBox(height: 18),
              if (_loading) const LinearProgressIndicator(),
              if (_error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error, style: Theme.of(context).textTheme.bodyMedium),
                ),
              const SizedBox(height: 12),
              Expanded(
                child: _results.isNotEmpty
                    ? ListView.separated(
                        itemCount: _results.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        physics: const BouncingScrollPhysics(),
                        cacheExtent: 800,
                        itemBuilder: (context, index) {
                          final item = _results[index];
                          return GlassPanel(
                            child: ListTile(
                              title: Text(item.name),
                              subtitle: Text('${item.symbol} · ${item.region}'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => CompanyDetailScreen(symbol: item.symbol),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      )
                    : _nyseListings.isNotEmpty
                        ? Column(
                            children: [
                              Expanded(
                                child: ListView.separated(
                                  itemCount: _pagedNyse.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                                  physics: const BouncingScrollPhysics(),
                                  cacheExtent: 800,
                                  itemBuilder: (context, index) {
                                    final item = _pagedNyse[index];
                                    return GlassPanel(
                                      child: ListTile(
                                        title: Text(item.name),
                                        subtitle: Text('${item.symbol} · ${item.exchange}'),
                                        trailing: const Icon(Icons.chevron_right),
                                        onTap: () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) => CompanyDetailScreen(symbol: item.symbol),
                                            ),
                                          );
                                        },
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  GlassPill(
                                    label: 'Previous',
                                    onTap: _pageIndex > 0
                                        ? () => setState(() => _pageIndex -= 1)
                                        : () {},
                                    compact: true,
                                  ),
                                  GlassPill(
                                    label: 'Next',
                                    onTap: (_pageIndex + 1) * _pageSize < _nyseListings.length
                                        ? () => setState(() => _pageIndex += 1)
                                        : () {},
                                    compact: true,
                                  ),
                                ],
                              ),
                            ],
                          )
                        : FutureBuilder<List<QuoteItem>>(
                            future: _featuredFuture,
                            builder: (context, snapshot) {
                              if (snapshot.connectionState == ConnectionState.waiting) {
                                return const Center(child: CircularProgressIndicator());
                              }
                              final items = snapshot.data ?? [];
                              return ListView.separated(
                                itemCount: items.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 12),
                                physics: const BouncingScrollPhysics(),
                                cacheExtent: 800,
                                itemBuilder: (context, index) {
                                  final item = items[index];
                                  return GlassPanel(
                                    child: ListTile(
                                      title: Text(item.name),
                                      subtitle: Text(item.symbol),
                                      trailing: SizedBox(
                                        width: 120,
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.end,
                                          children: [
                                            Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              crossAxisAlignment: CrossAxisAlignment.end,
                                              children: [
                                                Text('\$${item.price.toStringAsFixed(2)}'),
                                                Text(
                                                  '${item.changesPercentage.toStringAsFixed(2)}%',
                                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                        color: item.change >= 0 ? const Color(0xFF41D07B) : Colors.redAccent,
                                                      ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(width: 8),
                                            const Icon(Icons.chevron_right),
                                          ],
                                        ),
                                      ),
                                      onTap: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => CompanyDetailScreen(symbol: item.symbol),
                                          ),
                                        );
                                      },
                                    ),
                                  );
                                },
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CompanyDetailScreen extends StatefulWidget {
  const CompanyDetailScreen({super.key, required this.symbol});

  final String symbol;

  @override
  State<CompanyDetailScreen> createState() => _CompanyDetailScreenState();
}

class _CompanyDetailScreenState extends State<CompanyDetailScreen> {
  final ApiService _api = ApiService();
  late Future<CompanyDetailData> _detailFuture;

  @override
  void initState() {
    super.initState();
    _detailFuture = _loadDetail();
  }

  Future<CompanyDetailData> _loadDetail() async {
    final symbols = _resolveSymbols(widget.symbol);
    CompanyProfile? profile;
    CompanyQuote? quote;
    List<PeerCompany> peers = [];
    for (final symbol in symbols) {
      profile ??= await _api.fetchCompanyProfile(symbol);
      quote ??= await _api.fetchQuote(symbol);
      if (profile != null && quote != null) {
        try {
          peers = await _api.fetchPeerCompanies(profile.sector);
        } catch (_) {
          peers = [];
        }
        return CompanyDetailData(profile: profile, quote: quote, symbol: symbol, peers: peers);
      }
    }
    if (profile != null) {
      try {
        peers = await _api.fetchPeerCompanies(profile.sector);
      } catch (_) {
        peers = [];
      }
    }
    return CompanyDetailData(profile: profile, quote: quote, symbol: symbols.first, peers: peers);
  }

  List<String> _resolveSymbols(String symbol) {
    final upper = symbol.toUpperCase();
    if (upper == 'GOOGL' || upper == 'GOOG' || upper.contains('ALPHABET')) {
      return ['GOOGL', 'GOOG'];
    }
    if (upper == 'BRK.A' || upper == 'BRKA') {
      return ['BRK.A', 'BRK-A', 'BRKA'];
    }
    if (upper == 'BRK.B' || upper == 'BRKB') {
      return ['BRK.B', 'BRK-B', 'BRKB'];
    }
    return [symbol];
  }

  double _positionInRange({required double price, required double low, required double high}) {
    if (high <= low) return 0.5;
    return ((price - low) / (high - low)).clamp(0, 1);
  }

  double _healthScore(CompanyProfile profile, CompanyQuote? quote, double? sectorPeMedian) {
    double score = 0;
    // Profitability
    if (profile.eps > 0) score += 20;
    // Valuation vs sector median
    if (profile.pe > 0 && sectorPeMedian != null && sectorPeMedian > 0) {
      final ratio = (sectorPeMedian / profile.pe).clamp(0.5, 1.5);
      score += 20 * ((ratio - 0.5) / 1.0);
    }
    // Price location within 52-week range
    if (quote != null && profile.yearHigh > 0 && profile.yearLow > 0) {
      final pos = _positionInRange(price: quote.price, low: profile.yearLow, high: profile.yearHigh);
      score += (1 - (pos - 0.5).abs() * 2) * 20;
    } else {
      score += 10;
    }
    // Market cap stability
    if (profile.marketCap >= 200000000000) {
      score += 20;
    } else if (profile.marketCap >= 50000000000) {
      score += 15;
    } else if (profile.marketCap >= 10000000000) {
      score += 10;
    } else if (profile.marketCap > 0) {
      score += 6;
    }
    // Volatility proxy
    if (quote != null) {
      final change = quote.changesPercentage.abs();
      score += (change <= 1 ? 20 : (change <= 2.5 ? 12 : 6));
    } else {
      score += 8;
    }
    return score.clamp(0, 100);
  }

  String _scoreLabel(double score) {
    if (score >= 75) return 'Strong';
    if (score >= 55) return 'Balanced';
    return 'Cautious';
  }

  double? _medianPe(List<PeerCompany> peers) {
    final values = peers.map((e) => e.pe).where((v) => v > 0).toList()..sort();
    if (values.isEmpty) return null;
    final mid = values.length ~/ 2;
    if (values.length.isOdd) return values[mid];
    return (values[mid - 1] + values[mid]) / 2;
  }

  @override
  Widget build(BuildContext context) {
    return AppBackdrop(
      child: ResponsiveScaffold(
        selected: 2,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          child: FutureBuilder<CompanyDetailData>(
            future: _detailFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text('Unable to load company data.', style: Theme.of(context).textTheme.bodyLarge),
                );
              }
              final data = snapshot.data!;
              final profile = data.profile;
              final quote = data.quote;
              final peers = data.peers;
              final sectorMedianPe = peers.isNotEmpty ? _medianPe(peers) : null;
              final healthScore = profile == null ? null : _healthScore(profile, quote, sectorMedianPe);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back),
                      ),
                      const SizedBox(width: 8),
                      Text(data.symbol, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (profile == null && quote == null)
                    GlassPanel(
                      child: Text(
                        'No detailed data yet for this company. Try another symbol or reload later.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  if (profile != null)
                    GlassPanel(
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                            child: const Icon(Icons.business),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(profile.companyName, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                                const SizedBox(height: 4),
                                Text('${profile.sector} · ${profile.industry}', style: Theme.of(context).textTheme.bodySmall),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  if (quote != null)
                    GlassPanel(
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Price', style: Theme.of(context).textTheme.bodySmall),
                                const SizedBox(height: 6),
                                Text('\$${quote.price.toStringAsFixed(2)}', style: Theme.of(context).textTheme.headlineSmall),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Change', style: Theme.of(context).textTheme.bodySmall),
                                const SizedBox(height: 6),
                                Text('${quote.change.toStringAsFixed(2)} (${quote.changesPercentage.toStringAsFixed(2)}%)',
                                    style: Theme.of(context).textTheme.titleMedium),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Volume', style: Theme.of(context).textTheme.bodySmall),
                                const SizedBox(height: 6),
                                Text(_formatLarge(quote.volume), style: Theme.of(context).textTheme.titleMedium),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: GlassPanel(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Company Overview', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 10),
                            Text(profile?.description ?? 'No description available.', style: Theme.of(context).textTheme.bodyMedium),
                            const SizedBox(height: 16),
                            if (profile != null) ...[
                              HealthScorePanel(
                                score: healthScore ?? 0,
                                label: _scoreLabel(healthScore ?? 0),
                              ),
                              const SizedBox(height: 12),
                              PeerComparisonPanel(
                                profile: profile,
                                quote: quote,
                                sectorMedianPe: sectorMedianPe,
                                peersCount: peers.where((p) => p.pe > 0).length,
                              ),
                              const SizedBox(height: 12),
                            ],
                            if (profile != null) ...[
                              InfoRow(
                                label: 'Market Cap',
                                value: _formatLarge(profile.marketCap),
                                help: 'Total market value of all outstanding shares.',
                              ),
                              InfoRow(
                                label: 'P/E Ratio',
                                value: profile.pe.toStringAsFixed(2),
                                help: 'Price to earnings ratio. Lower can mean cheaper relative to earnings.',
                              ),
                              InfoRow(
                                label: 'EPS',
                                value: profile.eps.toStringAsFixed(2),
                                help: 'Earnings per share. Higher suggests stronger profitability.',
                              ),
                              InfoRow(
                                label: '52W Range',
                                value: '${profile.yearLow.toStringAsFixed(2)} - ${profile.yearHigh.toStringAsFixed(2)}',
                                help: 'Lowest and highest price over the last 52 weeks.',
                              ),
                              if (profile.website.isNotEmpty)
                                InfoRow(
                                  label: 'Website',
                                  value: profile.website,
                                  help: 'Official company website.',
                                ),
                            ],
                            if (quote != null && profile == null) ...[
                              InfoRow(label: 'Latest Price', value: '\$${quote.price.toStringAsFixed(2)}'),
                              InfoRow(label: 'Volume', value: _formatLarge(quote.volume)),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  String _formatLarge(double value) {
    if (value >= 1000000000000) {
      return '\$${(value / 1000000000000).toStringAsFixed(2)}T';
    }
    if (value >= 1000000000) {
      return '\$${(value / 1000000000).toStringAsFixed(2)}B';
    }
    if (value >= 1000000) {
      return '\$${(value / 1000000).toStringAsFixed(2)}M';
    }
    return '\$${value.toStringAsFixed(2)}';
  }
}

class CompanyDetailData {
  CompanyDetailData({required this.profile, required this.quote, required this.symbol, required this.peers});

  final CompanyProfile? profile;
  final CompanyQuote? quote;
  final String symbol;
  final List<PeerCompany> peers;
}

class SavedCompaniesScreen extends StatelessWidget {
  const SavedCompaniesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppBackdrop(
      child: ResponsiveScaffold(
        selected: 3,
        child: Center(
          child: GlassPanel(
            child: Text('Saved companies will appear here.', style: Theme.of(context).textTheme.bodyLarge),
          ),
        ),
      ),
    );
  }
}

class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? const [Color(0xFF0A1224), Color(0xFF0B1630), Color(0xFF0A1224)]
                : const [Color(0xFFF3F8FF), Color(0xFFE7F1FF), Color(0xFFF3F8FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -200,
              right: -120,
              child: GlowOrb(
                color: isDark ? const Color(0xFF203E7A) : const Color(0xFFB3D7F5),
                size: 320,
              ),
            ),
            Positioned(
              bottom: -220,
              left: -140,
              child: GlowOrb(
                color: isDark ? const Color(0xFF23335E) : const Color(0xFFAEC4FF),
                size: 340,
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

class GlowOrb extends StatelessWidget {
  const GlowOrb({super.key, required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withOpacity(0.5), color.withOpacity(0.02)],
        ),
      ),
    );
  }
}

class LogoButton extends StatefulWidget {
  const LogoButton({super.key, required this.size, required this.onTap});

  final double size;
  final VoidCallback onTap;

  @override
  State<LogoButton> createState() => _LogoButtonState();
}

class _LogoButtonState extends State<LogoButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color strokeColor = Theme.of(context).brightness == Brightness.dark ? const Color(0xFFBFD5EA) : scheme.primary;
    final double scale = _pressed
        ? 0.97
        : _hovered
            ? 1.08
            : 1;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.size / 3),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: _hovered ? 24 : 16, sigmaY: _hovered ? 24 : 16),
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  color: scheme.surface.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(widget.size / 3),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withOpacity(_hovered ? 0.25 : 0.15),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: CustomPaint(
                  painter: LogoPainter(color: strokeColor),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LogoPainter extends CustomPainter {
  const LogoPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.08
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final Path path = Path();
    path.moveTo(size.width * 0.2, size.height * 0.2);
    path.lineTo(size.width * 0.2, size.height * 0.8);
    path.lineTo(size.width * 0.8, size.height * 0.8);
    path.moveTo(size.width * 0.4, size.height * 0.65);
    path.lineTo(size.width * 0.4, size.height * 0.35);
    path.lineTo(size.width * 0.6, size.height * 0.5);
    path.lineTo(size.width * 0.8, size.height * 0.35);
    path.lineTo(size.width * 0.8, size.height * 0.65);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ResponsiveScaffold extends StatelessWidget {
  const ResponsiveScaffold({super.key, required this.selected, required this.child});

  final int selected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isWide = constraints.maxWidth >= 900;
        if (isWide) {
          return Row(
            children: [
              SideRail(selected: selected),
              Expanded(child: child),
            ],
          );
        }
        return Column(
          children: [
            Expanded(
              child: SafeArea(
                bottom: false,
                child: child,
              ),
            ),
            BottomNavigationBar(
              currentIndex: selected,
              onTap: (index) => AppNavigation.go(context, index),
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.grid_view_rounded), label: 'Dashboard'),
                BottomNavigationBarItem(icon: Icon(Icons.newspaper_rounded), label: 'News'),
                BottomNavigationBarItem(icon: Icon(Icons.work_outline_rounded), label: 'Companies'),
                BottomNavigationBarItem(icon: Icon(Icons.bookmark_border_rounded), label: 'Saved'),
                BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Profile'),
              ],
              type: BottomNavigationBarType.fixed,
            ),
          ],
        );
      },
    );
  }
}

class AppNavigation {
  static void go(BuildContext context, int index) {
    Widget target;
    switch (index) {
      case 0:
        target = const DashboardScreen();
        break;
      case 1:
        target = const NewsScreen();
        break;
      case 2:
        target = const CompaniesScreen();
        break;
      case 3:
        target = const SavedCompaniesScreen();
        break;
      case 4:
        ContactDialog.show(context);
        return;
      default:
        target = const DashboardScreen();
    }
    Navigator.of(context).pushReplacement(routeTo(target));
  }

  static PageRouteBuilder<void> routeTo(Widget target) {
    return PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) => target,
      transitionsBuilder: (_, animation, __, child) {
        final offset = Tween<Offset>(begin: const Offset(0.02, 0), end: Offset.zero).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        );
        final fade = Tween<double>(begin: 0, end: 1).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        );
        return FadeTransition(
          opacity: fade,
          child: SlideTransition(position: offset, child: child),
        );
      },
    );
  }
}

class ContactDialog {
  static void show(BuildContext context) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Contact',
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: GlassPanel(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Contact', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  _ContactRow(
                    label: 'Email',
                    value: 'joshuadsouza069@gmail.com',
                    onTap: () => _launchUrl('mailto:joshuadsouza069@gmail.com'),
                  ),
                  const SizedBox(height: 10),
                  _ContactRow(
                    label: 'Instagram',
                    value: 'instagram.com/__josh_24_',
                    onTap: () => _launchUrl('https://www.instagram.com/__josh_24_/'),
                  ),
                  const SizedBox(height: 10),
                  _ContactRow(
                    label: 'Phone',
                    value: '+44 7918689804',
                    onTap: () => _launchUrl('tel:+447918689804'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (_, animation, __, child) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
            child: child,
          ),
        );
      },
    );
  }

  static Future<void> _launchUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.label, required this.value, required this.onTap});

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(
          flex: 7,
          child: TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ),
      ],
    );
  }
}

class SideRail extends StatelessWidget {
  const SideRail({super.key, required this.selected});

  final int selected;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      width: 76,
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: scheme.surface.withOpacity(0.9),
        border: Border(right: BorderSide(color: scheme.onSurface.withOpacity(0.08))),
      ),
      child: Column(
        children: [
          LogoButton(
            size: 48,
            onTap: () {
              Navigator.of(context).pushReplacement(AppNavigation.routeTo(const SplashScreen()));
            },
          ),
          const SizedBox(height: 18),
          NavIconButton(
            icon: Icons.grid_view_rounded,
            active: selected == 0,
            onTap: () => AppNavigation.go(context, 0),
          ),
          const SizedBox(height: 12),
          NavIconButton(
            icon: Icons.newspaper_rounded,
            active: selected == 1,
            onTap: () => AppNavigation.go(context, 1),
          ),
          const SizedBox(height: 12),
          NavIconButton(
            icon: Icons.bookmark_border_rounded,
            active: selected == 3,
            onTap: () => AppNavigation.go(context, 3),
          ),
          const Spacer(),
          NavIconButton(
            icon: Icons.person_outline,
            active: false,
            onTap: () => ContactDialog.show(context),
          ),
        ],
      ),
    );
  }
}

class NavIconButton extends StatefulWidget {
  const NavIconButton({super.key, required this.icon, required this.active, required this.onTap});

  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  State<NavIconButton> createState() => _NavIconButtonState();
}

class _NavIconButtonState extends State<NavIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color base = widget.active ? scheme.primary.withOpacity(0.18) : Colors.transparent;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _hovered ? 1.08 : 1.0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _hovered ? scheme.primary.withOpacity(0.2) : base,
                borderRadius: BorderRadius.circular(14),
                boxShadow: _hovered
                    ? [
                        BoxShadow(
                          color: scheme.primary.withOpacity(0.25),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ]
                    : null,
              ),
              child: Icon(widget.icon, color: scheme.onSurface.withOpacity(0.7)),
            ),
          ),
        ),
      ),
    );
  }
}

class TopBar extends StatelessWidget {
  const TopBar({super.key, required this.title, required this.onSearch, required this.onAction});

  final String title;
  final ValueChanged<String> onSearch;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool compact = constraints.maxWidth < 700;
        return Row(
          children: [
            Text('Home', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.onSurface.withOpacity(0.6))),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, size: 16, color: scheme.onSurface.withOpacity(0.6)),
            const SizedBox(width: 6),
            Text(title, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.onSurface)),
            const Spacer(),
            if (compact)
              Expanded(child: SearchField(onSubmitted: onSearch))
            else
              SizedBox(width: 320, child: SearchField(onSubmitted: onSearch)),
            const SizedBox(width: 12),
            GlassIconButton(icon: Icons.notifications_none, onTap: onAction),
          ],
        );
      },
    );
  }
}

class SearchField extends StatelessWidget {
  const SearchField({super.key, required this.onSubmitted});

  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: TextField(
          onSubmitted: onSubmitted,
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.search, color: scheme.onSurface.withOpacity(0.6)),
            hintText: 'Search for companies...',
            filled: true,
            fillColor: scheme.surface.withOpacity(0.4),
            border: InputBorder.none,
            hintStyle: TextStyle(color: scheme.onSurface.withOpacity(0.45)),
          ),
          style: TextStyle(color: scheme.onSurface),
        ),
      ),
    );
  }
}

class GlassIconButton extends StatelessWidget {
  const GlassIconButton({super.key, required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.surface.withOpacity(0.5),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: scheme.onSurface.withOpacity(0.12)),
            ),
            child: Icon(icon, color: scheme.onSurface.withOpacity(0.75)),
          ),
        ),
      ),
    );
  }
}

class MarketCard extends StatelessWidget {
  const MarketCard({super.key, required this.title, required this.subtitle, required this.items, required this.positive});

  final String title;
  final String subtitle;
  final List<MarketItem> items;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(subtitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurface.withOpacity(0.6))),
          const SizedBox(height: 18),
          Expanded(
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => Divider(color: scheme.onSurface.withOpacity(0.08)),
              itemBuilder: (context, index) {
                final MarketItem item = items[index];
                return Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.name, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text(item.ticker, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurface.withOpacity(0.55))),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(item.value, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(
                          item.change,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: positive
                                    ? (item.change.startsWith('-') ? Colors.redAccent : const Color(0xFF41D07B))
                                    : Colors.redAccent,
                              ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class FeaturedCard extends StatelessWidget {
  const FeaturedCard({super.key, required this.title, required this.subtitle, required this.items, this.compact = false});

  final String title;
  final String subtitle;
  final List<QuoteItem> items;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final headerVisible = title.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (headerVisible) ...[
          Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(subtitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurface.withOpacity(0.6))),
          const SizedBox(height: 18),
        ],
        Expanded(
          child: ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => Divider(color: scheme.onSurface.withOpacity(0.08)),
            physics: const BouncingScrollPhysics(),
            cacheExtent: 400,
            itemBuilder: (context, index) {
              final item = items[index];
              final Color changeColor = item.change >= 0 ? const Color(0xFF41D07B) : Colors.redAccent;
              final String priceText = item.isLive ? '\$${item.price.toStringAsFixed(2)}' : '--';
              final String changeText = item.isLive ? '${item.changesPercentage.toStringAsFixed(2)}%' : 'Delayed';
              final String volumeText = item.isLive ? _formatVolume(item.volume) : 'Delayed';
              return Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(item.symbol, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurface.withOpacity(0.55))),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(priceText, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(
                        changeText,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: item.isLive ? changeColor : scheme.onSurface.withOpacity(0.5)),
                      ),
                      if (!compact) ...[
                        const SizedBox(height: 4),
                        Text(
                          volumeText,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurface.withOpacity(0.5)),
                        ),
                      ],
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  String _formatVolume(double value) {
    if (value >= 1000000000) {
      return 'Vol ${(value / 1000000000).toStringAsFixed(1)}B';
    }
    if (value >= 1000000) {
      return 'Vol ${(value / 1000000).toStringAsFixed(1)}M';
    }
    if (value >= 1000) {
      return 'Vol ${(value / 1000).toStringAsFixed(1)}K';
    }
    return 'Vol ${value.toStringAsFixed(0)}';
  }
}

class MarketItem {
  const MarketItem({required this.name, required this.ticker, required this.value, required this.change});

  final String name;
  final String ticker;
  final String value;
  final String change;
}

class DashboardData {
  DashboardData({
    required this.featured,
    required this.news,
    required this.macro,
    required this.events,
    required this.history,
  });

  final List<QuoteItem> featured;
  final List<NewsArticle> news;
  final List<QuoteItem> macro;
  final List<CalendarEvent> events;
  final List<HistoricalPoint> history;
}

class NewsArticle {
  NewsArticle({
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.source,
    required this.publishedAt,
    required this.url,
    required this.content,
  });

  final String title;
  final String description;
  final String imageUrl;
  final String source;
  final String publishedAt;
  final String url;
  final String content;

  factory NewsArticle.fromNewsApi(Map<String, dynamic> json) {
    return NewsArticle(
      title: json['title']?.toString() ?? 'Untitled',
      description: json['description']?.toString() ?? '',
      imageUrl: json['urlToImage']?.toString() ?? '',
      source: json['source']?['name']?.toString() ?? 'News',
      publishedAt: (json['publishedAt']?.toString() ?? '').split('T').first,
      url: json['url']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
    );
  }

  factory NewsArticle.fromFmp(Map<String, dynamic> json) {
    return NewsArticle(
      title: json['title']?.toString() ?? 'Untitled',
      description: json['text']?.toString() ?? '',
      imageUrl: json['image']?.toString() ?? '',
      source: json['site']?.toString() ?? 'Company News',
      publishedAt: (json['publishedDate']?.toString() ?? '').split(' ').first,
      url: json['url']?.toString() ?? '',
      content: json['text']?.toString() ?? '',
    );
  }

  factory NewsArticle.fromMarketaux(Map<String, dynamic> json) {
    return NewsArticle(
      title: json['title']?.toString() ?? 'Untitled',
      description: json['description']?.toString() ?? '',
      imageUrl: json['image_url']?.toString() ?? '',
      source: json['source']?.toString() ?? 'Marketaux',
      publishedAt: (json['published_at']?.toString() ?? '').split('T').first,
      url: json['url']?.toString() ?? '',
      content: json['snippet']?.toString() ?? '',
    );
  }
}

class CompanySearchItem {
  const CompanySearchItem({
    required this.symbol,
    required this.name,
    required this.exchange,
    required this.region,
  });

  final String symbol;
  final String name;
  final String exchange;
  final String region;

  factory CompanySearchItem.fromAlpha(Map<String, dynamic> json) {
    final exchange = json['4. region']?.toString() ?? '';
    return CompanySearchItem(
      symbol: json['1. symbol']?.toString() ?? '',
      name: json['2. name']?.toString() ?? '',
      exchange: exchange,
      region: exchange,
    );
  }

  factory CompanySearchItem.fromListing(String symbol, String name, String exchange) {
    return CompanySearchItem(
      symbol: symbol,
      name: name,
      exchange: exchange,
      region: exchange,
    );
  }

  factory CompanySearchItem.fromFmp(Map<String, dynamic> json) {
    final exchange = json['exchangeShortName']?.toString() ?? json['exchange']?.toString() ?? '';
    return CompanySearchItem(
      symbol: json['symbol']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      exchange: exchange,
      region: exchange,
    );
  }

  factory CompanySearchItem.fromFmpListing(Map<String, dynamic> json) {
    final exchange = json['exchangeShortName']?.toString() ?? json['exchange']?.toString() ?? '';
    return CompanySearchItem(
      symbol: json['symbol']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      exchange: exchange,
      region: exchange,
    );
  }
}

class CompanyProfile {
  CompanyProfile({
    required this.companyName,
    required this.description,
    required this.industry,
    required this.sector,
    required this.ceo,
    required this.website,
    required this.marketCap,
    required this.pe,
    required this.eps,
    required this.yearHigh,
    required this.yearLow,
  });

  final String companyName;
  final String description;
  final String industry;
  final String sector;
  final String ceo;
  final String website;
  final double marketCap;
  final double pe;
  final double eps;
  final double yearHigh;
  final double yearLow;

  factory CompanyProfile.fromAlpha(Map<String, dynamic> json) {
    double parseNum(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    return CompanyProfile(
      companyName: json['Name']?.toString() ?? '',
      description: json['Description']?.toString() ?? '',
      industry: json['Industry']?.toString() ?? '',
      sector: json['Sector']?.toString() ?? '',
      ceo: json['CEO']?.toString() ?? '',
      website: json['Website']?.toString() ?? '',
      marketCap: parseNum(json['MarketCapitalization']),
      pe: parseNum(json['PERatio']),
      eps: parseNum(json['EPS']),
      yearHigh: parseNum(json['52WeekHigh']),
      yearLow: parseNum(json['52WeekLow']),
    );
  }

  factory CompanyProfile.fromFmp(Map<String, dynamic> json) {
    double parseNum(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }
    double parseRangePart(String? range, {required bool high}) {
      if (range == null) return 0;
      final parts = range.split('-').map((part) => part.trim()).toList();
      if (parts.isEmpty) return 0;
      final value = high ? parts.last : parts.first;
      return double.tryParse(value) ?? 0;
    }

    return CompanyProfile(
      companyName: json['companyName']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      industry: json['industry']?.toString() ?? '',
      sector: json['sector']?.toString() ?? '',
      ceo: json['ceo']?.toString() ?? '',
      website: json['website']?.toString() ?? '',
      marketCap: parseNum(json['mktCap']),
      pe: parseNum(json['pe']),
      eps: parseNum(json['eps']),
      yearHigh: parseRangePart(json['range']?.toString(), high: true),
      yearLow: parseRangePart(json['range']?.toString(), high: false),
    );
  }
}

class PeerCompany {
  PeerCompany({required this.symbol, required this.companyName, required this.sector, required this.pe});

  final String symbol;
  final String companyName;
  final String sector;
  final double pe;

  factory PeerCompany.fromFmp(Map<String, dynamic> json) {
    double parseNum(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    return PeerCompany(
      symbol: json['symbol']?.toString() ?? '',
      companyName: json['companyName']?.toString() ?? json['name']?.toString() ?? '',
      sector: json['sector']?.toString() ?? '',
      pe: parseNum(json['pe']),
    );
  }
}

class CompanyQuote {
  CompanyQuote({
    required this.price,
    required this.change,
    required this.changesPercentage,
    required this.volume,
    required this.latestTradingDay,
  });

  final double price;
  final double change;
  final double changesPercentage;
  final double volume;
  final String latestTradingDay;

  factory CompanyQuote.fromAlpha(Map<String, dynamic> json) {
    double parseNum(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    return CompanyQuote(
      price: parseNum(json['05. price']),
      change: parseNum(json['09. change']),
      changesPercentage: parseNum((json['10. change percent'] ?? '').toString().replaceAll('%', '')),
      volume: parseNum(json['06. volume']),
      latestTradingDay: json['07. latest trading day']?.toString() ?? '',
    );
  }

  factory CompanyQuote.fromFmp(Map<String, dynamic> json) {
    double parseNum(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    return CompanyQuote(
      price: parseNum(json['price']),
      change: parseNum(json['change']),
      changesPercentage: parseNum(json['changesPercentage']),
      volume: parseNum(json['volume']),
      latestTradingDay: json['date']?.toString() ?? '',
    );
  }
}

class QuoteItem {
  QuoteItem({
    required this.symbol,
    required this.name,
    required this.price,
    required this.change,
    required this.changesPercentage,
    required this.volume,
    this.isLive = true,
  });

  final String symbol;
  final String name;
  final double price;
  final double change;
  final double changesPercentage;
  final double volume;
  final bool isLive;

  factory QuoteItem.fromAlphaQuote(Map<String, dynamic> json, String name) {
    double parseNum(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    return QuoteItem(
      symbol: json['01. symbol']?.toString() ?? '',
      name: name,
      price: parseNum(json['05. price']),
      change: parseNum(json['09. change']),
      changesPercentage: parseNum((json['10. change percent'] ?? '').toString().replaceAll('%', '')),
      volume: parseNum(json['06. volume']),
    );
  }

  factory QuoteItem.fromFmp(Map<String, dynamic> json) {
    double parseNum(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    return QuoteItem(
      symbol: json['symbol']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      price: parseNum(json['price']),
      change: parseNum(json['change']),
      changesPercentage: parseNum(json['changesPercentage']),
      volume: parseNum(json['volume']),
    );
  }
}

class GlassPanel extends StatelessWidget {
  const GlassPanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: scheme.surface.withOpacity(0.55),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: scheme.onSurface.withOpacity(0.1)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class DashboardPanel extends StatelessWidget {
  const DashboardPanel({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FrostedPill(
            label: title,
            tint: scheme.primary.withOpacity(0.18),
          ),
          const SizedBox(height: 16),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class MarketSummary {
  MarketSummary({
    required this.avgChange,
    required this.advancers,
    required this.decliners,
    required this.topMover,
    required this.bottomMover,
    required this.secondaryMover,
  });

  final String avgChange;
  final int advancers;
  final int decliners;
  final QuoteItem topMover;
  final QuoteItem bottomMover;
  final QuoteItem? secondaryMover;

  factory MarketSummary.empty() {
    final empty = QuoteItem(
      symbol: '--',
      name: 'No data',
      price: 0,
      change: 0,
      changesPercentage: 0,
      volume: 0,
      isLive: false,
    );
    return MarketSummary(
      avgChange: '0.00%',
      advancers: 0,
      decliners: 0,
      topMover: empty,
      bottomMover: empty,
      secondaryMover: null,
    );
  }

  String get topSymbol => topMover.symbol;
}

class MetricRow extends StatelessWidget {
  const MetricRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const Spacer(),
          Text(value, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class MiniMoverRow extends StatelessWidget {
  const MiniMoverRow({super.key, required this.item});

  final QuoteItem item;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color color = item.changesPercentage >= 0 ? const Color(0xFF41D07B) : Colors.redAccent;
    return Row(
      children: [
        Expanded(
          child: Text(item.symbol, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        ),
        Text(
          '${item.changesPercentage.toStringAsFixed(2)}%',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: item.isLive ? color : scheme.onSurface.withOpacity(0.5)),
        ),
      ],
    );
  }
}

enum QuickActionView { news, companies, saved }

class QuickActionsPanel extends StatefulWidget {
  const QuickActionsPanel({
    super.key,
    required this.featured,
    required this.summary,
    required this.news,
    required this.onNews,
    required this.onCompanies,
    required this.onSaved,
  });

  final List<QuoteItem> featured;
  final MarketSummary summary;
  final List<NewsArticle> news;
  final VoidCallback onNews;
  final VoidCallback onCompanies;
  final VoidCallback onSaved;

  @override
  State<QuickActionsPanel> createState() => _QuickActionsPanelState();
}

class _QuickActionsPanelState extends State<QuickActionsPanel> {
  QuickActionView _selected = QuickActionView.news;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final preview = widget.news.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            GlassPill(
              label: 'News',
              selected: _selected == QuickActionView.news,
              onTap: () => setState(() => _selected = QuickActionView.news),
            ),
            GlassPill(
              label: 'Companies',
              selected: _selected == QuickActionView.companies,
              onTap: () => setState(() => _selected = QuickActionView.companies),
            ),
            GlassPill(
              label: 'Saved',
              selected: _selected == QuickActionView.saved,
              onTap: () => setState(() => _selected = QuickActionView.saved),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: _QuickSection(
              title: _sectionTitle(),
              child: Column(
                children: [
                  if (_selected == QuickActionView.news)
                    preview.isEmpty
                        ? Text(
                            'No headlines yet. Tap refresh in News.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurface.withOpacity(0.65),
                                ),
                          )
                        : Column(
                            children: [
                              MiniNewsRow(article: preview[0]),
                              if (preview.length > 1) MiniNewsRow(article: preview[1]),
                              if (preview.length > 2) MiniNewsRow(article: preview[2]),
                            ],
                          ),
                  if (_selected == QuickActionView.companies)
                    Column(
                      children: [
                        if (widget.featured.isNotEmpty) MiniQuoteRow(item: widget.featured[0]),
                        if (widget.featured.length > 1) MiniQuoteRow(item: widget.featured[1]),
                        if (widget.featured.length > 2) MiniQuoteRow(item: widget.featured[2]),
                        const SizedBox(height: 10),
                        MiniMoverRow(item: widget.summary.topMover),
                        const SizedBox(height: 6),
                        MiniMoverRow(item: widget.summary.bottomMover),
                      ],
                    ),
                  if (_selected == QuickActionView.saved)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your saved companies will appear here.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurface.withOpacity(0.7),
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Pin tickers you want to track daily.',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: scheme.onSurface.withOpacity(0.55),
                              ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: GlassPill(
                      label: _ctaLabel(),
                      selected: true,
                      onTap: _ctaAction(),
                      compact: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _sectionTitle() {
    switch (_selected) {
      case QuickActionView.news:
        return 'Latest News';
      case QuickActionView.companies:
        return 'Company Snapshot';
      case QuickActionView.saved:
        return 'Saved Watchlist';
    }
  }

  String _ctaLabel() {
    switch (_selected) {
      case QuickActionView.news:
        return 'Go to News';
      case QuickActionView.companies:
        return 'Go to Companies';
      case QuickActionView.saved:
        return 'Go to Saved';
    }
  }

  VoidCallback _ctaAction() {
    switch (_selected) {
      case QuickActionView.news:
        return widget.onNews;
      case QuickActionView.companies:
        return widget.onCompanies;
      case QuickActionView.saved:
        return widget.onSaved;
    }
  }
}

class _QuickSection extends StatelessWidget {
  const _QuickSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surface.withOpacity(0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.onSurface.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface.withOpacity(0.8),
                ),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class MiniQuoteRow extends StatelessWidget {
  const MiniQuoteRow({super.key, required this.item});

  final QuoteItem item;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color color = item.changesPercentage >= 0 ? const Color(0xFF41D07B) : Colors.redAccent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(item.symbol, style: Theme.of(context).textTheme.bodySmall),
          ),
          Text(
            item.isLive ? '\$${item.price.toStringAsFixed(2)}' : '--',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurface.withOpacity(0.8)),
          ),
          const SizedBox(width: 8),
          Text(
            item.isLive ? '${item.changesPercentage.toStringAsFixed(2)}%' : '--',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: item.isLive ? color : scheme.onSurface.withOpacity(0.5)),
          ),
        ],
      ),
    );
  }
}

class MiniNewsRow extends StatelessWidget {
  const MiniNewsRow({super.key, required this.article});

  final NewsArticle article;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: article.url.isNotEmpty ? () => _launchExternal(article.url) : null,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      article.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${article.source} · ${article.publishedAt}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurface.withOpacity(0.6)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.open_in_new, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class ChecklistItemData {
  const ChecklistItemData({required this.label, required this.detail, this.done = false});

  final String label;
  final String detail;
  final bool done;

  ChecklistItemData copyWith({bool? done}) {
    return ChecklistItemData(label: label, detail: detail, done: done ?? this.done);
  }
}

class ChecklistPanel extends StatelessWidget {
  const ChecklistPanel({super.key, required this.items, required this.onToggle});

  final List<ChecklistItemData> items;
  final void Function(int index, bool value) onToggle;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = items[index];
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: scheme.surface.withOpacity(0.35),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.onSurface.withOpacity(0.08)),
          ),
          child: Row(
            children: [
              Checkbox(
                value: item.done,
                onChanged: (value) => onToggle(index, value ?? false),
                activeColor: scheme.primary,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.label,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.detail,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurface.withOpacity(0.6)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

enum CalendarEventType { economic, earnings }

class CalendarEvent {
  CalendarEvent({
    required this.date,
    required this.title,
    required this.subtitle,
    required this.type,
  });

  final DateTime date;
  final String title;
  final String subtitle;
  final CalendarEventType type;

  factory CalendarEvent.fromMap(Map<String, dynamic> json, {required CalendarEventType type}) {
    final dateRaw = json['date']?.toString() ?? json['datetime']?.toString() ?? json['publishedDate']?.toString() ?? '';
    final date = DateTime.tryParse(dateRaw) ?? DateTime.now();
    if (type == CalendarEventType.earnings) {
      final symbol = json['symbol']?.toString() ?? json['ticker']?.toString() ?? '';
      final name = json['company']?.toString() ?? json['companyName']?.toString() ?? json['name']?.toString() ?? '';
      final time = json['time']?.toString() ?? json['epsTime']?.toString() ?? '';
      final title = name.isNotEmpty ? name : (symbol.isNotEmpty ? symbol : 'Earnings');
      final subtitleParts = <String>[];
      if (symbol.isNotEmpty && title != symbol) subtitleParts.add(symbol);
      if (time.isNotEmpty) subtitleParts.add(time);
      return CalendarEvent(
        date: date,
        title: title,
        subtitle: subtitleParts.join(' · '),
        type: type,
      );
    }
    final event = json['event']?.toString() ?? json['eventName']?.toString() ?? json['name']?.toString() ?? 'Economic Event';
    final country = json['country']?.toString() ?? json['countryCode']?.toString() ?? '';
    final impact = json['impact']?.toString() ?? json['importance']?.toString() ?? '';
    final subtitle = [country, impact].where((part) => part.isNotEmpty).join(' · ');
    return CalendarEvent(date: date, title: event, subtitle: subtitle, type: type);
  }
}

class HistoricalPoint {
  const HistoricalPoint({required this.date, required this.value});

  final DateTime date;
  final double value;
}

class UpcomingEventsPanel extends StatelessWidget {
  const UpcomingEventsPanel({super.key, required this.events});

  final List<CalendarEvent> events;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    if (events.isEmpty) {
      return Text(
        'No upcoming events available.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurface.withOpacity(0.6)),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.zero,
      physics: const BouncingScrollPhysics(),
      itemCount: events.length.clamp(0, 8),
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final event = events[index];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: scheme.surface.withOpacity(0.35),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.onSurface.withOpacity(0.08)),
          ),
          child: Row(
            children: [
              _EventDateBadge(date: event.date),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (event.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        event.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurface.withOpacity(0.6)),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _EventTypePill(type: event.type),
            ],
          ),
        );
      },
    );
  }
}

class _EventDateBadge extends StatelessWidget {
  const _EventDateBadge({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final month = _shortMonth(date.month);
    return Container(
      width: 44,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: scheme.primary.withOpacity(0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.primary.withOpacity(0.25)),
      ),
      child: Column(
        children: [
          Text(
            month,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            date.day.toString(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _EventTypePill extends StatelessWidget {
  const _EventTypePill({required this.type});

  final CalendarEventType type;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool isEarnings = type == CalendarEventType.earnings;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (isEarnings ? scheme.secondary : scheme.primary).withOpacity(0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.onSurface.withOpacity(0.15)),
      ),
      child: Text(
        isEarnings ? 'Earnings' : 'Macro',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class TrendPanel extends StatelessWidget {
  const TrendPanel({super.key, required this.points});

  final List<HistoricalPoint> points;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    if (points.length < 2) {
      return Text(
        'Trend data not available yet.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurface.withOpacity(0.6)),
      );
    }
    final last = points.last;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'NASDAQ (Yearly)',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurface.withOpacity(0.7)),
        ),
        const SizedBox(height: 6),
        Text(
          _formatCompactPrice(last.value),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 140,
          width: double.infinity,
          child: CustomPaint(
            painter: TrendChartPainter(points: points, color: scheme.primary),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              points.first.date.year.toString(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurface.withOpacity(0.5)),
            ),
            Text(
              points.last.date.year.toString(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurface.withOpacity(0.5)),
            ),
          ],
        ),
      ],
    );
  }
}

class TrendChartPainter extends CustomPainter {
  TrendChartPainter({required this.points, required this.color});

  final List<HistoricalPoint> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final values = points.map((e) => e.value).toList();
    final double minVal = values.reduce((a, b) => a < b ? a : b);
    final double maxVal = values.reduce((a, b) => a > b ? a : b);
    final double range = (maxVal - minVal).abs() < 0.0001 ? 1 : (maxVal - minVal);
    final double dx = size.width / (points.length - 1);

    final Path line = Path();
    for (int i = 0; i < points.length; i++) {
      final point = points[i];
      final double norm = (point.value - minVal) / range;
      final double x = dx * i;
      final double y = size.height - (norm * size.height);
      if (i == 0) {
        line.moveTo(x, y);
      } else {
        line.lineTo(x, y);
      }
    }

    final Paint fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          color.withOpacity(0.2),
          color.withOpacity(0.02),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final Path fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    final Paint stroke = Paint()
      ..color = color.withOpacity(0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawPath(fill, fillPaint);
    canvas.drawPath(line, stroke);
  }

  @override
  bool shouldRepaint(covariant TrendChartPainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.color != color;
  }
}

class MarketTickerSpec {
  const MarketTickerSpec({required this.label, required this.symbol});

  final String label;
  final String symbol;
}

class MarketChip extends StatelessWidget {
  const MarketChip({super.key, required this.spec, required this.item});

  final MarketTickerSpec spec;
  final QuoteItem? item;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final QuoteItem? data = item;
    final bool live = data?.isLive == true;
    final double change = data?.changesPercentage ?? 0;
    final Color changeColor = change >= 0 ? const Color(0xFF41D07B) : Colors.redAccent;
    final String price = live ? _formatCompactPrice(data?.price ?? 0) : '--';
    final String pct = live ? '${change.toStringAsFixed(2)}%' : '--';
    return _InteractiveGlass(
      onTap: data == null ? null : () => _showMarketDetails(context, spec, data),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surface.withOpacity(0.45),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: scheme.onSurface.withOpacity(0.1)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              spec.label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface.withOpacity(0.75),
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              price,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              pct,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: live ? changeColor : scheme.onSurface.withOpacity(0.5)),
            ),
          ],
        ),
      ),
    );
  }
}

class _InteractiveGlass extends StatefulWidget {
  const _InteractiveGlass({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_InteractiveGlass> createState() => _InteractiveGlassState();
}

class _InteractiveGlassState extends State<_InteractiveGlass> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _hovered ? 1.06 : 1.0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: _hovered
                  ? [
                      BoxShadow(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.18),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

void _showMarketDetails(BuildContext context, MarketTickerSpec spec, QuoteItem item) {
  showDialog<void>(
    context: context,
    builder: (_) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: GlassPanel(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(spec.label, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(item.symbol, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                InfoRow(label: 'Price', value: _formatCompactPrice(item.price)),
                InfoRow(label: 'Change', value: '${item.change.toStringAsFixed(2)} (${item.changesPercentage.toStringAsFixed(2)}%)'),
                InfoRow(label: 'Volume', value: item.volume > 0 ? item.volume.toStringAsFixed(0) : '--'),
              ],
            ),
          ),
        ),
      );
    },
  );
}

String _formatCompactPrice(double value) {
  if (value.abs() >= 1000) {
    return value.toStringAsFixed(0);
  }
  if (value.abs() >= 100) {
    return value.toStringAsFixed(2);
  }
  if (value.abs() >= 1) {
    return value.toStringAsFixed(4);
  }
  return value.toStringAsFixed(6);
}

String _shortMonth(int month) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  if (month < 1 || month > 12) return '';
  return months[month - 1];
}

Future<void> _launchExternal(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

class MiniWatchRow extends StatelessWidget {
  const MiniWatchRow({super.key, required this.item});

  final QuoteItem item;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              item.name,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            item.isLive ? '\$${item.price.toStringAsFixed(2)}' : '--',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurface.withOpacity(0.85)),
          ),
        ],
      ),
    );
  }
}

class _FrostedPill extends StatelessWidget {
  const _FrostedPill({required this.label, required this.tint});

  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: tint,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: scheme.onSurface.withOpacity(0.2)),
          ),
          child: Text(label, style: Theme.of(context).textTheme.labelLarge),
        ),
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.label, required this.value, this.help});

  final String label;
  final String value;
  final String? help;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Row(
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurface.withOpacity(0.6))),
              if (help != null) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: help!,
                  child: Icon(Icons.info_outline, size: 14, color: scheme.onSurface.withOpacity(0.5)),
                ),
              ],
            ],
          ),
          const Spacer(),
          Text(value, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class HealthScorePanel extends StatelessWidget {
  const HealthScorePanel({super.key, required this.score, required this.label});

  final double score;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color color = score >= 75
        ? const Color(0xFF41D07B)
        : score >= 55
            ? scheme.primary
            : Colors.orangeAccent;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface.withOpacity(0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.onSurface.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Company Health Score', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurface.withOpacity(0.7))),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                score.toStringAsFixed(0),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: score / 100,
              minHeight: 6,
              backgroundColor: scheme.onSurface.withOpacity(0.08),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

class PeerComparisonPanel extends StatelessWidget {
  const PeerComparisonPanel({
    super.key,
    required this.profile,
    required this.quote,
    required this.sectorMedianPe,
    required this.peersCount,
  });

  final CompanyProfile profile;
  final CompanyQuote? quote;
  final double? sectorMedianPe;
  final int peersCount;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final double pe = profile.pe;
    final double? median = sectorMedianPe;
    final double? peDelta = (pe > 0 && median != null && median > 0) ? ((pe / median) - 1) * 100 : null;
    final double position = (quote != null && profile.yearHigh > 0 && profile.yearLow > 0)
        ? ((quote!.price - profile.yearLow) / (profile.yearHigh - profile.yearLow)).clamp(0, 1)
        : 0.5;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface.withOpacity(0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.onSurface.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Peer Comparison', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurface.withOpacity(0.7))),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: 'P/E vs sector',
                  value: peDelta == null ? '--' : '${peDelta >= 0 ? '+' : ''}${peDelta.toStringAsFixed(1)}%',
                  caption: peersCount > 0 ? 'Median of $peersCount peers' : 'Median unavailable',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MiniStat(
                  label: '52W position',
                  value: '${(position * 100).toStringAsFixed(0)}%',
                  caption: 'Low → High range',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, required this.caption});

  final String label;
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface.withOpacity(0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.onSurface.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurface.withOpacity(0.6))),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(caption, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurface.withOpacity(0.5))),
        ],
      ),
    );
  }
}

class NewsCard extends StatelessWidget {
  const NewsCard({
    super.key,
    required this.category,
    required this.title,
    required this.summary,
    required this.date,
    required this.imageUrl,
    required this.onOpen,
    required this.onDetails,
  });

  final String category;
  final String title;
  final String summary;
  final String date;
  final String imageUrl;
  final VoidCallback onOpen;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onOpen,
      child: GlassPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: imageUrl.isEmpty
                    ? Container(
                        color: scheme.primary.withOpacity(0.15),
                        child: Icon(Icons.insights, size: 44, color: scheme.onSurface.withOpacity(0.7)),
                      )
                    : Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) {
                          return Container(
                            color: scheme.primary.withOpacity(0.15),
                            child: Icon(Icons.insights, size: 44, color: scheme.onSurface.withOpacity(0.7)),
                          );
                        },
                      ),
              ),
            ),
            const SizedBox(height: 12),
            GlassPill(label: category, compact: true),
            const SizedBox(height: 10),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 6),
          Expanded(
            child: summary.isNotEmpty
                ? Text(
                    summary,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurface.withOpacity(0.6)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  )
                : const SizedBox.shrink(),
          ),
          Row(
            children: [
              Expanded(
                child: Text(date, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurface.withOpacity(0.55))),
              ),
                TextButton(
                  onPressed: onDetails,
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                  child: const Text('Details'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class GlassPill extends StatelessWidget {
  const GlassPill({super.key, required this.label, this.selected = false, this.compact = false, this.onTap});

  final String label;
  final bool selected;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final pill = _GlassPillSurface(
      label: label,
      compact: compact,
      selected: selected,
      scheme: scheme,
    );

    if (onTap == null) {
      return pill;
    }

    return _InteractivePill(
      onTap: onTap!,
      child: pill,
    );
  }
}

class _GlassPillSurface extends StatelessWidget {
  const _GlassPillSurface({
    required this.label,
    required this.compact,
    required this.selected,
    required this.scheme,
  });

  final String label;
  final bool compact;
  final bool selected;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16, vertical: compact ? 6 : 8),
          decoration: BoxDecoration(
            color: selected ? scheme.primary.withOpacity(0.18) : scheme.surface.withOpacity(0.5),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: scheme.onSurface.withOpacity(selected ? 0.25 : 0.12)),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: scheme.primary.withOpacity(0.2),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.onSurface.withOpacity(0.8))),
        ),
      ),
    );
  }
}

class _InteractivePill extends StatefulWidget {
  const _InteractivePill({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  State<_InteractivePill> createState() => _InteractivePillState();
}

class _InteractivePillState extends State<_InteractivePill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _hovered ? 1.06 : 1.0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              boxShadow: _hovered
                  ? [
                      BoxShadow(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
