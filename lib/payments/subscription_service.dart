import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// Thin wrapper around RevenueCat subscriptions.
///
/// Notes:
/// - On non-mobile platforms (macOS/Linux/Web), we default to free and do not
///   initialize purchases.
/// - This service is intentionally defensive so Flutter tests on desktop
///   won't crash due to missing platform channels.
class SubscriptionService {
  SubscriptionService._();

  static final SubscriptionService instance = SubscriptionService._();

  /// True when the user has an active subscription entitlement.
  final ValueNotifier<bool> isPremium = ValueNotifier<bool>(false);

  bool _configured = false;
  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  String _entitlementId() =>
      dotenv.env['REVENUECAT_ENTITLEMENT_ID'] ?? 'premium';

  Future<void> initialize() async {
    if (_configured) return;
    _configured = true;

    if (!_isMobile) {
      // Desktop/web: keep as free.
      isPremium.value = false;
      return;
    }

    final String apiKey = dotenv.env['REVENUECAT_API_KEY'] ?? '';
    if (apiKey.isEmpty) {
      // No configuration provided.
      isPremium.value = false;
      return;
    }

    try {
      Purchases.setLogLevel(LogLevel.debug);
      PurchasesConfiguration config = PurchasesConfiguration(apiKey);
      Purchases.configure(config);

      await _refreshCustomerInfo();
    } catch (_) {
      // Fail closed: treat as free.
      isPremium.value = false;
    }
  }

  Future<void> restorePurchases() async {
    if (!_isMobile) return;
    try {
      await Purchases.restorePurchases();
      await _refreshCustomerInfo();
    } catch (_) {
      // Ignore.
    }
  }

  Future<void> _refreshCustomerInfo() async {
    final customerInfo = await Purchases.getCustomerInfo();
    final entitlement = customerInfo.entitlements.active[_entitlementId()];
    isPremium.value = entitlement != null;
  }

  /// Triggers a subscription purchase flow (RevenueCat UI) when locked.
  Future<void> presentPaywall(BuildContext context) async {
    await initialize();
    if (isPremium.value) return;

    if (!_isMobile) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Premium'),
          content: const Text(
            'Subscriptions are only available on iOS/Android.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final String apiKey = dotenv.env['REVENUECAT_API_KEY'] ?? '';
    if (apiKey.isEmpty) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Premium not configured'),
          content: const Text(
            'Missing REVENUECAT_API_KEY. Add it to your .env file.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    try {
      final offerings = await Purchases.getOfferings();
      final offering = offerings.current;
      final packages = offering?.availablePackages ?? [];

      if (packages.isEmpty) {
        throw Exception('No available subscription packages found.');
      }

      // Show RevenueCat’s purchase UI for the first available package.
      await Purchases.purchase(PurchaseParams.package(packages.first));
      await _refreshCustomerInfo();
    } catch (_) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Upgrade failed'),
          content: const Text(
            'Unable to open the subscription screen. Please try again later.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }
}
