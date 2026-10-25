import 'package:flutter/foundation.dart';

import '../services/api_service.dart';

class CafeController extends ChangeNotifier {
  CafeController({required this.service, required this.session});

  static const pointsPerReward = loyaltyPointsPerReward;

  final ApiService service;
  final CafeSession? session;

  bool get isGuest => session == null;
  bool get canViewRecentOrders =>
      const {'owner', 'cashier'}.contains(session?.role);
  bool loading = true;
  bool placingOrder = false;
  bool redeemingReward = false;
  bool refreshingRecentOrders = false;
  String? errorMessage;
  String? orderErrorMessage;
  String? redemptionErrorMessage;
  String? recentOrdersErrorMessage;
  String? lastOrderId;
  LoyaltyRedemption? lastRedemption;
  List<CafeProduct> products = const [];
  List<InventoryItem> inventory = const [];
  List<CafeOrder> recentOrders = const [];
  MemberProfile profile = const MemberProfile(fullName: '', loyaltyPoints: 0);
  final Map<String, int> _cart = {};

  int get cartItemCount =>
      _cart.values.fold(0, (sum, quantity) => sum + quantity);

  List<CafeProduct> get cartProducts =>
      products.where((product) => _cart.containsKey(product.id)).toList();

  int quantityFor(CafeProduct product) => _cart[product.id] ?? 0;

  double get cartTotal => cartProducts.fold(
    0,
    (total, product) => total + product.price * quantityFor(product),
  );

  int get lowStockCount => inventory.where((item) => item.isLow).length;

  int get rewardsAvailable => profile.loyaltyPoints ~/ pointsPerReward;
  int get pointsToNextReward =>
      pointsPerReward - profile.loyaltyPoints % pointsPerReward;
  bool get canRedeemReward =>
      session?.role == 'loyal_customer' &&
      !loading &&
      !redeemingReward &&
      rewardsAvailable > 0 &&
      products.any((product) => product.isAvailable);

  Future<void> load() async {
    loading = true;
    errorMessage = null;
    recentOrdersErrorMessage = null;
    notifyListeners();
    try {
      final loadedProducts = await service.fetchProducts();
      products = loadedProducts;
      final currentSession = session;
      if (currentSession == null) {
        inventory = const [];
        recentOrders = const [];
        profile = const MemberProfile(fullName: 'Guest', loyaltyPoints: 0);
      } else {
        inventory = const [];
        recentOrders = const [];
        profile = MemberProfile(
          fullName: currentSession.username,
          loyaltyPoints: 0,
        );

        // These endpoints have different role permissions. Keep the public
        // menu available even if an account cannot access an optional panel.
        if (const {'owner', 'cashier', 'staff'}.contains(currentSession.role)) {
          try {
            inventory = await service.fetchInventory();
          } catch (_) {
            inventory = const [];
          }
        } else if (currentSession.role == 'loyal_customer') {
          try {
            profile = await service.fetchProfile(currentSession);
          } catch (_) {
            profile = MemberProfile(
              fullName: currentSession.username,
              loyaltyPoints: 0,
            );
          }
        }
        if (canViewRecentOrders) await refreshRecentOrders();
      }
    } catch (error) {
      errorMessage = _friendlyError(error);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> refreshRecentOrders() async {
    if (!canViewRecentOrders || refreshingRecentOrders) return;
    refreshingRecentOrders = true;
    recentOrdersErrorMessage = null;
    notifyListeners();
    try {
      recentOrders = await service.fetchRecentOrders();
    } catch (error) {
      recentOrdersErrorMessage = _friendlyError(error);
    } finally {
      refreshingRecentOrders = false;
      notifyListeners();
    }
  }

  void addToCart(CafeProduct product) {
    if (placingOrder || !product.isAvailable) return;
    _cart.update(product.id, (quantity) => quantity + 1, ifAbsent: () => 1);
    lastOrderId = null;
    notifyListeners();
  }

  void removeFromCart(CafeProduct product) {
    if (placingOrder) return;
    final quantity = quantityFor(product);
    if (quantity <= 1) {
      _cart.remove(product.id);
    } else {
      _cart[product.id] = quantity - 1;
    }
    notifyListeners();
  }

  void clearCart() {
    if (placingOrder) return;
    _cart.clear();
    notifyListeners();
  }

  void startNewOrder() {
    if (placingOrder) return;
    lastOrderId = null;
    orderErrorMessage = null;
    notifyListeners();
  }

  Future<String> submitOrder({required String customerName}) async {
    if (placingOrder) {
      throw StateError('An order is already being submitted.');
    }
    if (_cart.isEmpty) throw StateError('Add an item before placing an order.');
    placingOrder = true;
    orderErrorMessage = null;
    notifyListeners();
    try {
      final referenceCode = await service.createKioskOrder(
        customerName: customerName,
        customerUserId: session?.userId,
        items: _cart.entries
            .map((entry) => {'product_id': entry.key, 'quantity': entry.value})
            .toList(),
      );
      _cart.clear();
      lastOrderId = referenceCode;
      return referenceCode;
    } catch (error) {
      orderErrorMessage = _friendlyError(error);
      rethrow;
    } finally {
      placingOrder = false;
      notifyListeners();
    }
  }

  Future<LoyaltyRedemption> redeemReward(CafeProduct product) async {
    if (redeemingReward) {
      throw StateError('A reward is already being redeemed.');
    }
    if (session?.role != 'loyal_customer') {
      throw StateError('Sign in to a loyalty account to redeem a reward.');
    }
    if (profile.loyaltyPoints < pointsPerReward) {
      throw StateError('You need 10 points to redeem an item.');
    }
    if (!products.any((item) => item.id == product.id && item.isAvailable)) {
      throw StateError('Choose an available menu item to redeem.');
    }
    redeemingReward = true;
    redemptionErrorMessage = null;
    notifyListeners();
    try {
      final redemption = await service.redeemLoyalty(productId: product.id);
      profile = MemberProfile(
        fullName: profile.fullName,
        loyaltyPoints: redemption.points,
        earningsCount: profile.earningsCount,
        redemptionsCount: profile.redemptionsCount + 1,
        activity: [
          LoyaltyActivity(
            title: '${redemption.productName} reward',
            detail:
                '-${redemption.pointsSpent} points · ${redemption.rewardCode}',
            createdAt: DateTime.now(),
            isRedemption: true,
          ),
          ...profile.activity,
        ],
      );
      lastRedemption = redemption;
      return redemption;
    } catch (error) {
      redemptionErrorMessage = _friendlyError(error);
      rethrow;
    } finally {
      redeemingReward = false;
      notifyListeners();
    }
  }

  static String _friendlyError(Object error) {
    if (error is StateError) return error.message.toString();
    final message = error.toString();
    return message
        .replaceFirst('Exception: ', '')
        .replaceFirst('StateError: ', '');
  }
}
