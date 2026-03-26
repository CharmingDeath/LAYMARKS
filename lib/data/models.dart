class CompanyDetailData {
  CompanyDetailData({
    required this.profile,
    required this.quote,
    required this.symbol,
    required this.series,
  });

  final CompanyProfile? profile;
  final CompanyQuote? quote;
  final String symbol;
  final List<double> series;
}

class MarketItem {
  const MarketItem({
    required this.name,
    required this.ticker,
    required this.value,
    required this.change,
  });

  final String name;
  final String ticker;
  final String value;
  final String change;
}

class DashboardData {
  DashboardData({
    required this.featured,
    required this.macro,
    required this.news,
    required this.series,
    this.earningsEvents = const [],
    this.economicEvents = const [],
    this.focus,
    this.focusProfile,
  });

  final List<QuoteItem> featured;
  final List<QuoteItem> macro;
  final List<NewsArticle> news;
  final Map<String, List<double>> series;
  final List<EarningsCalendarEvent> earningsEvents;
  final List<EconomicCalendarEvent> economicEvents;
  final QuoteItem? focus;
  final CompanyProfile? focusProfile;
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

  factory CompanySearchItem.fromListing(
    String symbol,
    String name,
    String exchange,
  ) {
    return CompanySearchItem(
      symbol: symbol,
      name: name,
      exchange: exchange,
      region: exchange,
    );
  }

  factory CompanySearchItem.fromFmp(Map<String, dynamic> json) {
    final exchange =
        json['exchangeShortName']?.toString() ??
        json['exchange']?.toString() ??
        '';
    return CompanySearchItem(
      symbol: json['symbol']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      exchange: exchange,
      region: exchange,
    );
  }

  factory CompanySearchItem.fromFmpListing(Map<String, dynamic> json) {
    final exchange =
        json['exchangeShortName']?.toString() ??
        json['exchange']?.toString() ??
        '';
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
      changesPercentage: parseNum(
        (json['10. change percent'] ?? '').toString().replaceAll('%', ''),
      ),
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
      changesPercentage: parseNum(
        (json['10. change percent'] ?? '').toString().replaceAll('%', ''),
      ),
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

class CompanyFinancials {
  CompanyFinancials({
    required this.symbol,
    required this.period,
    required this.reportDate,
    required this.revenue,
    required this.netIncome,
    required this.totalAssets,
    required this.totalLiabilities,
    required this.operatingCashFlow,
    required this.freeCashFlow,
  });

  final String symbol;
  final String period;
  final String reportDate;
  final double revenue;
  final double netIncome;
  final double totalAssets;
  final double totalLiabilities;
  final double operatingCashFlow;
  final double freeCashFlow;

  static double _num(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static Map<String, dynamic> _firstRow(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is List && value.isNotEmpty && value.first is Map<String, dynamic>) {
      return value.first as Map<String, dynamic>;
    }
    return const {};
  }

  factory CompanyFinancials.fromProxy(Map<String, dynamic> json) {
    final income = _firstRow(json, 'income');
    final balance = _firstRow(json, 'balance');
    final cashflow = _firstRow(json, 'cashflow');
    final reportDate =
        income['date']?.toString() ??
        balance['date']?.toString() ??
        cashflow['date']?.toString() ??
        '';
    return CompanyFinancials(
      symbol: json['symbol']?.toString() ?? '',
      period: json['period']?.toString() ?? 'quarter',
      reportDate: reportDate,
      revenue: _num(income['revenue']),
      netIncome: _num(income['netIncome']),
      totalAssets: _num(balance['totalAssets']),
      totalLiabilities: _num(balance['totalLiabilities']),
      operatingCashFlow: _num(cashflow['operatingCashFlow']),
      freeCashFlow: _num(cashflow['freeCashFlow']),
    );
  }
}

class PeerCompany {
  PeerCompany({
    required this.symbol,
    required this.name,
    required this.sector,
    required this.price,
    required this.changePercent,
    required this.marketCap,
  });

  final String symbol;
  final String name;
  final String sector;
  final double price;
  final double changePercent;
  final double marketCap;

  factory PeerCompany.fromFmp(Map<String, dynamic> json) {
    double parseNum(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    return PeerCompany(
      symbol: json['symbol']?.toString() ?? '',
      name: json['companyName']?.toString() ?? json['name']?.toString() ?? '',
      sector: json['sector']?.toString() ?? '',
      price: parseNum(json['price']),
      changePercent: parseNum(json['changesPercentage']),
      marketCap: parseNum(json['marketCap']),
    );
  }
}

class EconomicCalendarEvent {
  EconomicCalendarEvent({
    required this.date,
    required this.country,
    required this.event,
    required this.impact,
    required this.actual,
    required this.previous,
    required this.estimate,
  });

  final String date;
  final String country;
  final String event;
  final String impact;
  final String actual;
  final String previous;
  final String estimate;

  factory EconomicCalendarEvent.fromFmp(Map<String, dynamic> json) {
    return EconomicCalendarEvent(
      date: json['date']?.toString() ?? '',
      country: json['country']?.toString() ?? '',
      event: json['event']?.toString() ?? '',
      impact: json['impact']?.toString() ?? '',
      actual: json['actual']?.toString() ?? '',
      previous: json['previous']?.toString() ?? '',
      estimate: json['estimate']?.toString() ?? '',
    );
  }
}

class EarningsCalendarEvent {
  EarningsCalendarEvent({
    required this.date,
    required this.symbol,
    required this.eps,
    required this.epsEstimated,
    required this.revenue,
    required this.revenueEstimated,
    required this.time,
  });

  final String date;
  final String symbol;
  final double eps;
  final double epsEstimated;
  final double revenue;
  final double revenueEstimated;
  final String time;

  factory EarningsCalendarEvent.fromFmp(Map<String, dynamic> json) {
    double parseNum(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    return EarningsCalendarEvent(
      date: json['date']?.toString() ?? '',
      symbol: json['symbol']?.toString() ?? '',
      eps: parseNum(json['eps']),
      epsEstimated: parseNum(json['epsEstimated']),
      revenue: parseNum(json['revenue']),
      revenueEstimated: parseNum(json['revenueEstimated']),
      time: json['time']?.toString() ?? '',
    );
  }
}
