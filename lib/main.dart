import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data/api_service.dart';
import 'data/models.dart';
import 'navigation/app_navigation.dart';
import 'payments/subscription_service.dart';
import 'widgets/common_widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  try {
    await SubscriptionService.instance.initialize();
  } catch (_) {
    // Treat as free if subscription initialization fails.
  }
  runApp(const AppMineApp());
}

class AppMineApp extends StatelessWidget {
  const AppMineApp({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = GoogleFonts.interTextTheme();
    return MaterialApp(
      title: 'LAYMARKS',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3069E0)),
        textTheme: textTheme,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3069E0),
          brightness: Brightness.dark,
        ),
        textTheme: textTheme,
        useMaterial3: true,
      ),
      initialRoute: AppRoutes.splash,
      routes: {
        AppRoutes.splash: (_) => const SplashScreen(),
        AppRoutes.dashboard: (_) => const DashboardScreen(),
        AppRoutes.news: (_) => const NewsScreen(),
        AppRoutes.companies: (_) => const CompaniesScreen(),
        AppRoutes.saved: (_) => const SavedScreen(),
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

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final ApiService _api = ApiService();
  late Future<DashboardData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
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
    final focus = featured.isNotEmpty ? featured.first : null;
    final focusProfile = focus == null
        ? null
        : await _api.fetchCompanyProfile(focus.symbol);
    return DashboardData(
      featured: featured,
      macro: macro,
      news: news.take(6).toList(),
      series: series,
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
                  const TopBar(title: 'Dashboard'),
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
    return ValueListenableBuilder<bool>(
      valueListenable: SubscriptionService.instance.isPremium,
      builder: (context, premium, _) {
        return GlassPanel(
          child: Column(
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
                Text(profile.website.isEmpty ? '' : profile.website),
                if (!premium) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Premium unlocks CEO, valuation and 52-week range.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: () =>
                        SubscriptionService.instance.presentPaywall(context),
                    child: const Text('Upgrade to Premium'),
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  Text('Sector: ${profile.sector}'),
                  const SizedBox(height: 6),
                  Text('CEO: ${profile.ceo}'),
                  const SizedBox(height: 6),
                  Text('Market Cap: \$${profile.marketCap.toStringAsFixed(0)}'),
                  const SizedBox(height: 6),
                  Text('P/E: ${profile.pe.toStringAsFixed(2)}'),
                  const SizedBox(height: 6),
                  Text('EPS: ${profile.eps.toStringAsFixed(2)}'),
                  const SizedBox(height: 6),
                  Text(
                    '52-week: \$${profile.yearLow.toStringAsFixed(2)} - \$${profile.yearHigh.toStringAsFixed(2)}',
                  ),
                ],
              ],
            ],
          ),
        );
      },
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
  late Future<List<NewsArticle>> _future;

  @override
  void initState() {
    super.initState();
    _future = _api.fetchTopNews();
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
              const TopBar(title: 'Market News'),
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
                    return ValueListenableBuilder<bool>(
                      valueListenable: SubscriptionService.instance.isPremium,
                      builder: (context, premium, _) {
                        const int freeLimit = 12;
                        final int limit = premium
                            ? news.length
                            : news.length.clamp(0, freeLimit);
                        final visible = news.take(limit).toList();

                        return Column(
                          children: [
                            if (!premium && news.length > visible.length) ...[
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Upgrade to Premium to unlock more news articles.',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurface
                                                  .withValues(alpha: 0.7),
                                            ),
                                      ),
                                    ),
                                    FilledButton(
                                      onPressed: () => SubscriptionService
                                          .instance
                                          .presentPaywall(context),
                                      child: const Text('Upgrade'),
                                    ),
                                  ],
                                ),
                              ),
                            ],
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
                                    onDetails: () =>
                                        _showDetails(context, article),
                                  );
                                },
                              ),
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
  late Future<List<CompanySearchItem>> _future;
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    _future = _api.fetchAllListings();
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
                    final items = snapshot.data ?? [];
                    return ValueListenableBuilder<bool>(
                      valueListenable: SubscriptionService.instance.isPremium,
                      builder: (context, premium, _) {
                        const int freeLimit = 120;
                        final int limit = premium
                            ? items.length
                            : items.length.clamp(0, freeLimit);
                        final visible = items.take(limit).toList();

                        final bool truncated =
                            !premium && items.length > visible.length;

                        return GlassPanel(
                          child: Column(
                            children: [
                              if (truncated) ...[
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Upgrade to Premium to unlock more company results.',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurface
                                                    .withValues(alpha: 0.7),
                                              ),
                                        ),
                                      ),
                                      FilledButton(
                                        onPressed: () => SubscriptionService
                                            .instance
                                            .presentPaywall(context),
                                        child: const Text('Upgrade'),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              Expanded(
                                child: ListView.separated(
                                  itemCount: visible.length,
                                  separatorBuilder: (_, index) =>
                                      const Divider(),
                                  itemBuilder: (context, index) {
                                    final item = visible[index];
                                    return ListTile(
                                      title: Text(
                                        '${item.name} (${item.symbol})',
                                      ),
                                      subtitle: Text(item.exchange),
                                      onTap: () =>
                                          _showCompanyDetails(context, item),
                                    );
                                  },
                                ),
                              ),
                            ],
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

  Future<void> _showCompanyDetails(
    BuildContext context,
    CompanySearchItem item,
  ) async {
    final profile = await _api.fetchCompanyProfile(item.symbol);
    final quote = await _api.fetchQuote(item.symbol);
    if (!context.mounted) return;
    final priceText = quote == null
        ? 'N/A'
        : '\$${quote.price.toStringAsFixed(2)}';
    final bool premium = SubscriptionService.instance.isPremium.value;
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
              Text(profile?.description ?? 'No profile information available.'),
              if (profile != null && premium) ...[
                const SizedBox(height: 12),
                Text('Sector: ${profile.sector}'),
                const SizedBox(height: 6),
                Text('Industry: ${profile.industry}'),
                const SizedBox(height: 6),
                Text('CEO: ${profile.ceo}'),
                const SizedBox(height: 6),
                Text('Website: ${profile.website}'),
                const SizedBox(height: 12),
                Text('Market Cap: \$${profile.marketCap.toStringAsFixed(0)}'),
                const SizedBox(height: 6),
                Text('P/E: ${profile.pe.toStringAsFixed(2)}'),
                const SizedBox(height: 6),
                Text('EPS: ${profile.eps.toStringAsFixed(2)}'),
                const SizedBox(height: 6),
                Text(
                  '52-week: \$${profile.yearLow.toStringAsFixed(2)} - \$${profile.yearHigh.toStringAsFixed(2)}',
                ),
              ],
              if (profile != null && !premium) ...[
                const SizedBox(height: 12),
                Text(
                  'Premium unlocks CEO, valuation (P/E, EPS), market cap, and 52-week range.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (!premium)
            FilledButton(
              onPressed: () async {
                await SubscriptionService.instance.presentPaywall(context);
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('Upgrade to Premium'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          if (!premium)
            TextButton(
              onPressed: () async {
                await SubscriptionService.instance.restorePurchases();
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('Restore'),
            ),
        ],
      ),
    );
  }
}

class SavedScreen extends StatefulWidget {
  const SavedScreen({super.key});

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  final ApiService _api = ApiService();
  late Future<List<NewsArticle>> _future;

  @override
  void initState() {
    super.initState();
    _future = _api.fetchCompanyNews();
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
              const TopBar(title: 'Saved / Watchlist Feed'),
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
                    final articles = snapshot.data ?? [];
                    return GlassPanel(
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
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: GlassPanel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(details, textAlign: TextAlign.center),
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
