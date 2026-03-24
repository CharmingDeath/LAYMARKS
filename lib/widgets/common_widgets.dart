import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/models.dart';
import '../navigation/app_navigation.dart';

class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? const [
                    Color(0xFF0A1224),
                    Color(0xFF0B1630),
                    Color(0xFF0A1224),
                  ]
                : const [
                    Color(0xFFF3F8FF),
                    Color(0xFFE7F1FF),
                    Color(0xFFF3F8FF),
                  ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: child,
      ),
    );
  }
}

class ResponsiveScaffold extends StatelessWidget {
  const ResponsiveScaffold({
    super.key,
    required this.selected,
    required this.child,
  });

  final int selected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1000;
        if (isWide) {
          return Row(
            children: [
              SideRail(selected: selected),
              Expanded(child: SafeArea(child: child)),
            ],
          );
        }
        return Column(
          children: [
            Expanded(child: SafeArea(bottom: false, child: child)),
            BottomNavigationBar(
              currentIndex: selected,
              onTap: (index) => AppNavigation.go(context, index),
              type: BottomNavigationBarType.fixed,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.grid_view_rounded),
                  label: 'Dashboard',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.newspaper_rounded),
                  label: 'News',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.business_rounded),
                  label: 'Companies',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.bookmark_border_rounded),
                  label: 'Saved',
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class SideRail extends StatelessWidget {
  const SideRail({super.key, required this.selected});

  final int selected;

  @override
  Widget build(BuildContext context) {
    return NavigationRail(
      selectedIndex: selected,
      onDestinationSelected: (index) => AppNavigation.go(context, index),
      labelType: NavigationRailLabelType.all,
      destinations: const [
        NavigationRailDestination(
          icon: Icon(Icons.grid_view_rounded),
          label: Text('Dashboard'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.newspaper_rounded),
          label: Text('News'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.business_rounded),
          label: Text('Companies'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.bookmark_border_rounded),
          label: Text('Saved'),
        ),
      ],
      trailing: Expanded(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: IconButton(
            tooltip: 'Contact',
            onPressed: () => ContactDialog.show(context),
            icon: const Icon(Icons.person_outline),
          ),
        ),
      ),
    );
  }
}

class TopBar extends StatelessWidget {
  const TopBar({super.key, required this.title, this.onSearch});

  final String title;
  final ValueChanged<String>? onSearch;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const Spacer(),
        if (onSearch != null)
          SizedBox(
            width: 280,
            child: TextField(
              onSubmitted: onSearch,
              decoration: const InputDecoration(
                hintText: 'Search companies...',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
      ],
    );
  }
}

class GlassPanel extends StatelessWidget {
  const GlassPanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surface.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(16),
          ),
          child: child,
        ),
      ),
    );
  }
}

class FeaturedCard extends StatelessWidget {
  const FeaturedCard({super.key, required this.items});

  final List<QuoteItem> items;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: ListView.separated(
        itemCount: items.length,
        separatorBuilder: (_, index) => const Divider(),
        itemBuilder: (context, index) {
          final item = items[index];
          return ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${item.name} (${item.symbol})'),
            subtitle: Text('Vol ${item.volume.toStringAsFixed(0)}'),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('\$${item.price.toStringAsFixed(2)}'),
                Text(
                  '${item.changesPercentage.toStringAsFixed(2)}%',
                  style: TextStyle(
                    color: item.change >= 0 ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class NewsCard extends StatelessWidget {
  const NewsCard({
    super.key,
    required this.article,
    required this.onOpen,
    required this.onDetails,
  });

  final NewsArticle article;
  final VoidCallback onOpen;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(article.source, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 6),
          Text(
            article.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            article.description.isEmpty ? article.content : article.description,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          Row(
            children: [
              Text(
                article.publishedAt,
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const Spacer(),
              TextButton(onPressed: onDetails, child: const Text('Details')),
              TextButton(onPressed: onOpen, child: const Text('Open')),
            ],
          ),
        ],
      ),
    );
  }
}

class ContactDialog {
  static void show(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Contact'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Email: joshuadsouza069@gmail.com'),
            SizedBox(height: 8),
            Text('Instagram: instagram.com/__josh_24_/'),
            SizedBox(height: 8),
            Text('Phone: +44 7918689804'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => _launchUrl('mailto:joshuadsouza069@gmail.com'),
            child: const Text('Email'),
          ),
          TextButton(
            onPressed: () =>
                _launchUrl('https://www.instagram.com/__josh_24_/'),
            child: const Text('Instagram'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  static Future<void> _launchUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
