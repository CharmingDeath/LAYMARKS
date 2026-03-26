import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'data/api_service.dart';
import 'data/models.dart';
import 'monetization/subscription_service.dart';
import 'navigation/app_navigation.dart';
import 'widgets/common_widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    dotenv.testLoad(fileInput: '');
  }
  runApp(const AppMineApp());
}

class AppMineApp extends StatelessWidget {
  const AppMineApp({super.key});

  @override
  Widget build(BuildContext context) {
    final lightTextTheme = GoogleFonts.interTextTheme();
    final darkBase = ThemeData(brightness: Brightness.dark).textTheme;
    final darkTextTheme = GoogleFonts.interTextTheme(darkBase);
    return MaterialApp(
      title: 'LAYMARKS',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3069E0)),
        textTheme: lightTextTheme,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3069E0),
          brightness: Brightness.dark,
        ),
        textTheme: darkTextTheme,
        useMaterial3: true,
      ),
      initialRoute: AppRoutes.splash,
      routes: {
        AppRoutes.splash: (_) => const SplashScreen(),
        AppRoutes.dashboard: (_) => const DashboardScreen(),
        AppRoutes.news: (_) => const NewsScreen(),
        AppRoutes.companies: (_) => const CompaniesScreen(),
        AppRoutes.saved: (_) => const SavedScreen(),
        AppRoutes.upgrade: (_) => const UpgradeScreen(),
      },
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _navTimer;

  @override
  void initState() {
    super.initState();
    _navTimer = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(AppRoutes.dashboard);
    });
  }

  @override
  void dispose() {
    _navTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppBackdrop(
      child: Center(
        child: Text(
          'LAYMARKS',
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 1.8,
          ),
        ),
      ),
    );
  }
}

class UpgradeScreen extends StatefulWidget {
  const UpgradeScreen({super.key});

  @override
  State<UpgradeScreen> createState() => _UpgradeScreenState();
}

class _UpgradeScreenState extends State<UpgradeScreen> {
  final SubscriptionService _subscription = SubscriptionService.instance;
  bool _isLoading = true;
  bool _isRestoring = false;
  List<ProductDetails> _products = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await _subscription.init();
      final products = await _subscription.loadProducts();
      if (!mounted) return;
      setState(() {
        _products = products;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _restore() async {
    setState(() => _isRestoring = true);
    try {
      await _subscription.restorePurchases();
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      if (_subscription.isPremium) {
        Navigator.of(context).pop();
      }
    } finally {
      if (!mounted) return;
      setState(() => _isRestoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppBackdrop(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Upgrade to Premium',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    PaywallCard(
                      products: _products,
                      onPurchase: (product) async {
                        await _subscription.buyProduct(product);
                        await Future<void>.delayed(const Duration(milliseconds: 500));
                        if (!mounted) return;
                        if (_subscription.isPremium) {
                          Navigator.of(context).pop();
                        }
                      },
                      onRestore: _isRestoring ? null : _restore,
                      restoring: _isRestoring,
                      errorText: _error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Subscription terms',
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Payment will be charged to your App Store or Google Play account '
                      'at confirmation of purchase. Subscription renews automatically '
                      'unless canceled at least 24 hours before the end of the current period. '
                      'You can manage and cancel subscriptions from your store account settings.',
                    ),
                  ],
                ),
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
  final SubscriptionService _subscription = SubscriptionService.instance;
  late Future<DashboardData> _future;

  @override
  void initState() {
    super.initState();
    _subscription.init();
    _subscription.addListener(_onSubscriptionChanged);
    _future = _load();
  }

  void _onSubscriptionChanged() {
    if (!mounted) return;
    setState(() {
      _future = _load();
    });
  }

  @override
  void dispose() {
    _subscription.removeListener(_onSubscriptionChanged);
    super.dispose();
  }

  Future<DashboardData> _load() async {
    final featuredSymbols = ['AAPL', 'MSFT', 'TSLA', 'NVDA', 'AMZN'];
    final macroSymbols = ['SPY', 'QQQ', 'DIA', 'IWM', 'TLT'];
    final allQuotes = await _api.fetchQuotes([
      ...featuredSymbols,
      ...macroSymbols,
    ]);
    final featured = allQuotes
        .where((q) => featuredSymbols.contains(q.symbol))
        .toList();
    final macro = allQuotes
        .where((q) => macroSymbols.contains(q.symbol))
        .toList();
    final series = await _api.fetchIntradaySeriesMap(
      featured.map((q) => q.symbol).toList(),
      points: 24,
    );
    final news = await _api.fetchTopNews();
    List<EarningsCalendarEvent> earningsEvents = [];
    List<EconomicCalendarEvent> economicEvents = [];
    try {
      earningsEvents = _subscription.isPremium
          ? await _api.fetchEarningsCalendar()
          : const [];
    } catch (_) {
      earningsEvents = [];
    }
    try {
      economicEvents = _subscription.isPremium
          ? await _api.fetchEconomicCalendar()
          : const [];
    } catch (_) {
      economicEvents = [];
    }
    final focus = featured.isNotEmpty ? featured.first : null;
    final focusProfile = focus == null
        ? null
        : await _api.fetchCompanyProfile(focus.symbol);
    return DashboardData(
      featured: featured,
      macro: macro,
      news: news.take(6).toList(),
      series: series,
      earningsEvents: earningsEvents.take(6).toList(),
      economicEvents: economicEvents.take(6).toList(),
      focus: focus,
      focusProfile: focusProfile,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppBackdrop(
      child: ResponsiveScaffold(
        selected: 0,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FutureBuilder<DashboardData>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return _ErrorState(
                  title: 'Dashboard failed to load',
                  details: '${snapshot.error}',
                  onRetry: () => setState(() => _future = _load()),
                );
              }
              final data = snapshot.data!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TopBar(
                    title: 'Dashboard',
                    trailing: !_subscription.isPremium
                        ? const _UpgradeButton()
                        : null,
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final wide = c.maxWidth >= 1150;
                        if (wide) {
                          return Row(
                            children: [
                              Expanded(
                                child: FeaturedCard(items: data.featured),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: FeaturedCard(items: data.macro)),
                              const SizedBox(width: 12),
                              Expanded(child: _FocusPanel(data: data)),
                            ],
                          );
                        }
                        return ListView(
                          children: [
                            SizedBox(
                              height: 300,
                              child: FeaturedCard(items: data.featured),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 300,
                              child: FeaturedCard(items: data.macro),
                            ),
                            const SizedBox(height: 12),
                            _FocusPanel(data: data),
                          ],
                        );
                      },
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
}

class _FocusPanel extends StatelessWidget {
  const _FocusPanel({required this.data});

  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    final focus = data.focus;
    final profile = data.focusProfile;
    final isPremium = SubscriptionService.instance.isPremium;
    return GlassPanel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Focus company',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          if (focus == null)
            const Text('No quote available')
          else ...[
            Text('${focus.name} (${focus.symbol})'),
            const SizedBox(height: 6),
            Text('\$${focus.price.toStringAsFixed(2)}'),
            Text('Change ${focus.changesPercentage.toStringAsFixed(2)}%'),
          ],
          const SizedBox(height: 16),
          if (profile != null) ...[
            Text(
              profile.industry.isEmpty
                  ? 'Industry unavailable'
                  : profile.industry,
            ),
            const SizedBox(height: 4),
            if (profile.website.isNotEmpty)
              GestureDetector(
                onTap: () => _openUrl(profile.website),
                child: Text(
                  profile.website,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
          ],
          const SizedBox(height: 18),
          Text(
            'Upcoming earnings',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          if (!isPremium)
            _PremiumLockBanner(
              message: 'Unlock earnings and economic calendars with Premium.',
            )
          else if (data.earningsEvents.isEmpty)
            const Text('No upcoming earnings in range.')
          else
            ...data.earningsEvents.take(3).map(
              (event) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${event.date} • ${event.symbol} • '
                  'EPS ${event.epsEstimated.toStringAsFixed(2)} est',
                ),
              ),
            ),
          const SizedBox(height: 10),
          Text(
            'Economic calendar',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          if (!isPremium)
            const SizedBox.shrink()
          else if (data.economicEvents.isEmpty)
            const Text('No economic events in range.')
          else
            ...data.economicEvents.take(3).map(
              (event) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${event.date} • ${event.country} • ${event.event}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openUrl(String rawUrl) async {
    Uri? uri = Uri.tryParse(rawUrl.trim());
    if (uri == null) return;
    if (uri.scheme.isEmpty) {
      uri = Uri.tryParse('https://${rawUrl.trim()}');
      if (uri == null) return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  final ApiService _api = ApiService();
  final SubscriptionService _subscription = SubscriptionService.instance;
  late Future<List<NewsArticle>> _future;

  @override
  void initState() {
    super.initState();
    _subscription.init();
    _subscription.addListener(_onSubscriptionChanged);
    _future = _api.fetchTopNews();
  }

  void _onSubscriptionChanged() {
    if (!mounted) return;
    setState(() => _future = _api.fetchTopNews());
  }

  @override
  void dispose() {
    _subscription.removeListener(_onSubscriptionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppBackdrop(
      child: ResponsiveScaffold(
        selected: 1,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TopBar(
                title: 'Market News',
                trailing: !_subscription.isPremium
                    ? const _UpgradeButton()
                    : null,
              ),
              const SizedBox(height: 14),
              Expanded(
                child: FutureBuilder<List<NewsArticle>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return _ErrorState(
                        title: 'News failed to load',
                        details: '${snapshot.error}',
                        onRetry: () =>
                            setState(() => _future = _api.fetchTopNews()),
                      );
                    }
                    final news = snapshot.data ?? [];
                    if (news.isEmpty) {
                      return const Center(child: Text('No articles available'));
                    }
                    final visible = _subscription.isPremium
                        ? news
                        : news.take(8).toList();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!_subscription.isPremium)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: _PremiumLockBanner(
                              message:
                                  'Premium unlocks full news feed history and unlimited access.',
                            ),
                          ),
                        Expanded(
                          child: GridView.builder(
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 440,
                                  childAspectRatio: 1.3,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                ),
                            itemCount: visible.length,
                            itemBuilder: (context, index) {
                              final article = visible[index];
                              return NewsCard(
                                article: article,
                                onOpen: () => _openUrl(article.url),
                                onDetails: () => _showDetails(context, article),
                              );
                            },
                          ),
                        ),
                      ],
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

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _showDetails(BuildContext context, NewsArticle article) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(article.title),
        content: Text(
          article.content.isEmpty ? article.description : article.content,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _openUrl(article.url);
            },
            child: const Text('Open'),
          ),
        ],
      ),
    );
  }
}

class CompaniesScreen extends StatefulWidget {
  const CompaniesScreen({super.key});

  @override
  State<CompaniesScreen> createState() => _CompaniesScreenState();
}

class _CompaniesScreenState extends State<CompaniesScreen> {
  final ApiService _api = ApiService();
  final SubscriptionService _subscription = SubscriptionService.instance;
  late Future<List<CompanySearchItem>> _future;
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    _subscription.init();
    _subscription.addListener(_onSubscriptionChanged);
    _future = _api.fetchAllListings();
  }

  void _onSubscriptionChanged() {
    if (!mounted) return;
    setState(() {
      _future = _lastQuery.isEmpty
          ? _api.fetchAllListings()
          : _api.searchCompanies(_lastQuery);
    });
  }

  @override
  void dispose() {
    _subscription.removeListener(_onSubscriptionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppBackdrop(
      child: ResponsiveScaffold(
        selected: 2,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TopBar(
                title: 'Companies',
                trailing: !_subscription.isPremium
                    ? const _UpgradeButton()
                    : null,
                onSearch: (q) {
                  final query = q.trim();
                  if (query.isEmpty) {
                    setState(() {
                      _lastQuery = '';
                      _future = _api.fetchAllListings();
                    });
                    return;
                  }
                  setState(() {
                    _lastQuery = query;
                    _future = _api.searchCompanies(query);
                  });
                },
              ),
              const SizedBox(height: 14),
              Expanded(
                child: FutureBuilder<List<CompanySearchItem>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return _ErrorState(
                        title: 'Company data failed to load',
                        details: '${snapshot.error}',
                        onRetry: () => setState(() {
                          _future = _lastQuery.isEmpty
                              ? _api.fetchAllListings()
                              : _api.searchCompanies(_lastQuery);
                        }),
                      );
                    }
                    final allItems = snapshot.data ?? [];
                    final items = _subscription.isPremium
                        ? allItems
                        : allItems.take(120).toList();
                    return GlassPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!_subscription.isPremium)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 12),
                              child: _PremiumLockBanner(
                                message:
                                    'Premium unlocks full listings, full company details, and peers.',
                              ),
                            ),
                          Expanded(
                            child: ListView.separated(
                              itemCount: items.length,
                              separatorBuilder: (_, index) => const Divider(),
                              itemBuilder: (context, index) {
                                final item = items[index];
                                return ListTile(
                                  title: Text('${item.name} (${item.symbol})'),
                                  subtitle: Text(item.exchange),
                                  onTap: () {
                                    if (!_subscription.isPremium) {
                                      Navigator.of(
                                        context,
                                      ).pushNamed(AppRoutes.upgrade);
                                      return;
                                    }
                                    _showCompanyDetails(context, item);
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      ),
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

  Future<void> _showCompanyDetails(
    BuildContext context,
    CompanySearchItem item,
  ) async {
    CompanyProfile? profile;
    CompanyQuote? quote;
    CompanyFinancials? financials;
    List<PeerCompany> peers = [];

    try {
      profile = await _api.fetchCompanyProfile(item.symbol);
    } catch (_) {
      profile = null;
    }
    try {
      quote = await _api.fetchQuote(item.symbol);
    } catch (_) {
      quote = null;
    }
    try {
      financials = await _api.fetchCompanyFinancials(item.symbol);
    } catch (_) {
      financials = null;
    }
    final sector = profile?.sector.trim() ?? '';
    if (sector.isNotEmpty) {
      try {
        peers = await _api.fetchPeers(sector);
      } catch (_) {
        peers = [];
      }
    }

    if (!context.mounted) return;
    final priceText = quote == null
        ? 'N/A'
        : '\$${quote.price.toStringAsFixed(2)}';
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${item.name} (${item.symbol})'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Exchange: ${item.exchange}'),
              const SizedBox(height: 8),
              Text('Price: $priceText'),
              const SizedBox(height: 8),
              if (profile?.sector.isNotEmpty ?? false) ...[
                Text('Sector: ${profile!.sector}'),
                const SizedBox(height: 8),
              ],
              if (financials != null) ...[
                Text(
                  'Latest ${financials.period} financials (${financials.reportDate}):',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  'Revenue: ${_compactMoney(financials.revenue)} • '
                  'Net income: ${_compactMoney(financials.netIncome)}',
                ),
                const SizedBox(height: 4),
                Text(
                  'Assets: ${_compactMoney(financials.totalAssets)} • '
                  'Liabilities: ${_compactMoney(financials.totalLiabilities)}',
                ),
                const SizedBox(height: 4),
                Text(
                  'Op CF: ${_compactMoney(financials.operatingCashFlow)} • '
                  'Free CF: ${_compactMoney(financials.freeCashFlow)}',
                ),
                const SizedBox(height: 10),
              ],
              if (peers.isNotEmpty) ...[
                Text(
                  'Sector peers',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                ...peers.take(5).map(
                  (peer) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${peer.symbol}  ${peer.name.isEmpty ? '' : '• ${peer.name}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Text(profile?.description ?? 'No profile information available.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _compactMoney(double value) {
    if (value == 0) return '\$0';
    final abs = value.abs();
    String suffix = '';
    double scaled = value;
    if (abs >= 1000000000000) {
      suffix = 'T';
      scaled = value / 1000000000000;
    } else if (abs >= 1000000000) {
      suffix = 'B';
      scaled = value / 1000000000;
    } else if (abs >= 1000000) {
      suffix = 'M';
      scaled = value / 1000000;
    } else if (abs >= 1000) {
      suffix = 'K';
      scaled = value / 1000;
    }
    return '\$${scaled.toStringAsFixed(abs >= 1000 ? 2 : 0)}$suffix';
  }
}

class SavedScreen extends StatefulWidget {
  const SavedScreen({super.key});

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  final ApiService _api = ApiService();
  final SubscriptionService _subscription = SubscriptionService.instance;
  late Future<List<NewsArticle>> _future;

  @override
  void initState() {
    super.initState();
    _subscription.init();
    _subscription.addListener(_onSubscriptionChanged);
    _future = _api.fetchCompanyNews();
  }

  void _onSubscriptionChanged() {
    if (!mounted) return;
    setState(() => _future = _api.fetchCompanyNews());
  }

  @override
  void dispose() {
    _subscription.removeListener(_onSubscriptionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppBackdrop(
      child: ResponsiveScaffold(
        selected: 3,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TopBar(
                title: 'Company News Feed',
                trailing: !_subscription.isPremium
                    ? const _UpgradeButton()
                    : null,
              ),
              const SizedBox(height: 14),
              Expanded(
                child: FutureBuilder<List<NewsArticle>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return _ErrorState(
                        title: 'Feed failed to load',
                        details: '${snapshot.error}',
                        onRetry: () =>
                            setState(() => _future = _api.fetchCompanyNews()),
                      );
                    }
                    final allArticles = snapshot.data ?? [];
                    final articles = _subscription.isPremium
                        ? allArticles
                        : allArticles.take(10).toList();
                    return GlassPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!_subscription.isPremium)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 12),
                              child: _PremiumLockBanner(
                                message:
                                    'Premium unlocks unlimited company news feed and full watchlist workflow.',
                              ),
                            ),
                          Expanded(
                            child: ListView.separated(
                              itemCount: articles.length,
                              separatorBuilder: (_, index) => const Divider(),
                              itemBuilder: (context, index) {
                                final article = articles[index];
                                return ListTile(
                                  title: Text(article.title),
                                  subtitle: Text(
                                    '${article.source} - ${article.publishedAt}',
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
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

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.title,
    required this.details,
    required this.onRetry,
  });

  final String title;
  final String details;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final displayDetails = kReleaseMode
        ? 'Something went wrong while loading data. Please try again.'
        : details;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: GlassPanel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(displayDetails, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: onRetry, child: const Text('Retry')),
              if (!AppSecrets.isReady) ...[
                const SizedBox(height: 10),
                Text(
                  'Missing env keys: ${AppSecrets.missingKeys().join(', ')}',
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}


class _PremiumLockBanner extends StatelessWidget {
  const _PremiumLockBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _UpgradeButton extends StatelessWidget {
  const _UpgradeButton();

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => Navigator.of(context).pushNamed(AppRoutes.upgrade),
      icon: const Icon(Icons.workspace_premium),
      label: const Text('Upgrade'),
    );
  }
}
