import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SubscriptionPlan {
  const SubscriptionPlan({
    required this.id,
    required this.title,
    required this.subtitle,
  });

  final String id;
  final String title;
  final String subtitle;
}

class SubscriptionState {
  const SubscriptionState({
    required this.storeAvailable,
    required this.isPremium,
    required this.isLoading,
    required this.products,
    required this.error,
    required this.activeProductId,
  });

  final bool storeAvailable;
  final bool isPremium;
  final bool isLoading;
  final List<ProductDetails> products;
  final String? error;
  final String? activeProductId;

  SubscriptionState copyWith({
    bool? storeAvailable,
    bool? isPremium,
    bool? isLoading,
    List<ProductDetails>? products,
    String? error,
    String? activeProductId,
  }) {
    return SubscriptionState(
      storeAvailable: storeAvailable ?? this.storeAvailable,
      isPremium: isPremium ?? this.isPremium,
      isLoading: isLoading ?? this.isLoading,
      products: products ?? this.products,
      error: error,
      activeProductId: activeProductId ?? this.activeProductId,
    );
  }

  static const SubscriptionState initial = SubscriptionState(
    storeAvailable: false,
    isPremium: false,
    isLoading: true,
    products: [],
    error: null,
    activeProductId: null,
  );
}

class SubscriptionService extends ChangeNotifier {
  SubscriptionService._();

  static final SubscriptionService instance = SubscriptionService._();

  // Configure these exact IDs in App Store Connect and Google Play Console.
  static const String monthlyProductId = 'laymarks_premium_monthly';
  static const String yearlyProductId = 'laymarks_premium_yearly';
  static const Set<String> productIds = <String>{
    monthlyProductId,
    yearlyProductId,
  };

  static const String _premiumKey = 'premium_active';
  static const String _premiumProductKey = 'premium_product_id';

  final InAppPurchase _iap = InAppPurchase.instance;
  final StreamController<SubscriptionState> _controller =
      StreamController<SubscriptionState>.broadcast();

  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  SubscriptionState _state = SubscriptionState.initial;
  bool _initialized = false;

  Stream<SubscriptionState> get stream => _controller.stream;
  SubscriptionState get state => _state;
  bool get isPremium => _state.isPremium;
  bool get isLoading => _state.isLoading;
  String? get error => _state.error;
  bool get storeAvailable => _state.storeAvailable;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    _emit(_state.copyWith(isLoading: true, error: null));

    final prefs = await SharedPreferences.getInstance();
    final restoredPremium = prefs.getBool(_premiumKey) ?? false;
    final restoredProductId = prefs.getString(_premiumProductKey);

    _emit(
      _state.copyWith(
        isPremium: restoredPremium,
        activeProductId: restoredProductId,
      ),
    );

    _purchaseSub = _iap.purchaseStream.listen(
      _onPurchaseUpdates,
      onError: (Object error) {
        _emit(_state.copyWith(error: 'Purchase stream error: $error'));
      },
    );

    final available = await _iap.isAvailable();
    if (!available) {
      _emit(
        _state.copyWith(
          storeAvailable: false,
          isLoading: false,
          error: 'Store is unavailable on this device.',
        ),
      );
      return;
    }

    final response = await _iap.queryProductDetails(productIds);
    if (response.error != null) {
      _emit(
        _state.copyWith(
          storeAvailable: true,
          isLoading: false,
          error: response.error!.message,
        ),
      );
      return;
    }

    final products = response.productDetails.toList()
      ..sort((a, b) => a.rawPrice.compareTo(b.rawPrice));
    _emit(
      _state.copyWith(
        storeAvailable: true,
        isLoading: false,
        products: products,
        error: null,
      ),
    );
  }

  Future<void> buy(ProductDetails product) async {
    if (!_state.storeAvailable) {
      _emit(_state.copyWith(error: 'Store is unavailable.'));
      return;
    }
    _emit(_state.copyWith(isLoading: true, error: null));
    final param = PurchaseParam(productDetails: product);
    final started = await _iap.buyNonConsumable(purchaseParam: param);
    if (!started) {
      _emit(
        _state.copyWith(
          isLoading: false,
          error: 'Unable to start purchase flow.',
        ),
      );
    }
  }

  Future<List<ProductDetails>> loadProducts() async {
    if (!_initialized) {
      await init();
    }
    return _state.products;
  }

  Future<void> buyProduct(ProductDetails product) => buy(product);

  Future<void> restorePurchases() async {
    if (!_state.storeAvailable) {
      _emit(_state.copyWith(error: 'Store is unavailable.'));
      return;
    }
    _emit(_state.copyWith(isLoading: true, error: null));
    await _iap.restorePurchases();
    _emit(_state.copyWith(isLoading: false));
  }

  List<SubscriptionPlan> plansForUi() {
    return const [
      SubscriptionPlan(
        id: monthlyProductId,
        title: 'LAYMARKS Pro Monthly',
        subtitle: 'Full access, billed monthly.',
      ),
      SubscriptionPlan(
        id: yearlyProductId,
        title: 'LAYMARKS Pro Yearly',
        subtitle: 'Best value, billed annually.',
      ),
    ];
  }

  ProductDetails? productById(String id) {
    for (final product in _state.products) {
      if (product.id == id) return product;
    }
    return null;
  }

  Future<void> _onPurchaseUpdates(List<PurchaseDetails> purchases) async {
    var premiumUnlocked = _state.isPremium;
    String? productId = _state.activeProductId;

    for (final purchase in purchases) {
      if (!productIds.contains(purchase.productID)) {
        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }
        continue;
      }

      switch (purchase.status) {
        case PurchaseStatus.pending:
          _emit(_state.copyWith(isLoading: true, error: null));
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          premiumUnlocked = true;
          productId = purchase.productID;
          break;
        case PurchaseStatus.error:
          _emit(
            _state.copyWith(
              isLoading: false,
              error: purchase.error?.message ?? 'Purchase failed.',
            ),
          );
          break;
        case PurchaseStatus.canceled:
          _emit(
            _state.copyWith(
              isLoading: false,
              error: 'Purchase canceled.',
            ),
          );
          break;
      }

      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }

    await _persistPremium(premiumUnlocked, productId);
    _emit(
      _state.copyWith(
        isPremium: premiumUnlocked,
        activeProductId: productId,
        isLoading: false,
        error: null,
      ),
    );
  }

  Future<void> _persistPremium(bool isPremium, String? productId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_premiumKey, isPremium);
    if (productId == null || productId.isEmpty) {
      await prefs.remove(_premiumProductKey);
      return;
    }
    await prefs.setString(_premiumProductKey, productId);
  }

  void _emit(SubscriptionState state) {
    _state = state;
    if (!_controller.isClosed) {
      _controller.add(state);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _purchaseSub?.cancel();
    _controller.close();
    super.dispose();
  }
}
