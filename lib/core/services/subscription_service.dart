// lib/core/services/subscription_service.dart
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:flutter/services.dart'; // ← ADD THIS for PlatformException

class SubscriptionService {
  static const String _entitlementId = 'network_access';
  static const String _monthlyProductId = 'moneygigs_network_monthly';

  /// Check if user has active subscription
  Future<bool> hasActiveSubscription() async {
    try {
      final customerInfo = await Purchases.getCustomerInfo();

      // Check if user has the network_access entitlement
      final hasEntitlement = customerInfo.entitlements.all[_entitlementId]?.isActive ?? false;

      print('📊 Subscription status: ${hasEntitlement ? "ACTIVE" : "INACTIVE"}');
      return hasEntitlement;
    } catch (e) {
      print('❌ Error checking subscription: $e');
      return false;
    }
  }

  /// Get available subscription products
  Future<List<StoreProduct>> getProducts() async {
    try {
      final offerings = await Purchases.getOfferings();

      if (offerings.current == null) {
        print('⚠️ No offerings configured in RevenueCat');
        return [];
      }

      final products = offerings.current!.availablePackages
          .map((package) => package.storeProduct)
          .toList();

      print('📦 Found ${products.length} products');
      return products;
    } catch (e) {
      print('❌ Error fetching products: $e');
      return [];
    }
  }


  /// Purchase monthly subscription
  Future<bool> purchaseMonthlySubscription() async {
    try {
      print('💳 Starting purchase...');

      // Get offerings
      final offerings = await Purchases.getOfferings();
      if (offerings.current == null) {
        print('❌ No offerings available');
        return false;
      }

      // Find the monthly package
      final package = offerings.current!.monthly;
      if (package == null) {
        print('❌ Monthly package not found in offerings');
        // Check what packages ARE available
        final available = offerings.current!.availablePackages;
        print('📦 Available packages: ${available.map((p) => p.identifier).toList()}');
        return false;
      }

      print('💳 Purchasing package: ${package.identifier}');

      // Make purchase - returns CustomerInfo now, not PurchaseResult
      final purchaseResult = await Purchases.purchasePackage(package);

      // Get customer info from result
      final customerInfo = purchaseResult.customerInfo;

      // Check if purchase was successful
      final hasEntitlement = customerInfo.entitlements.all[_entitlementId]?.isActive ?? false;

      if (hasEntitlement) {
        print('✅ Purchase successful!');
        return true;
      } else {
        print('⚠️ Purchase completed but entitlement not active');
        return false;
      }

    } on PlatformException catch (e) {
      final errorCode = PurchasesErrorHelper.getErrorCode(e);

      if (errorCode == PurchasesErrorCode.purchaseCancelledError) {
        print('ℹ️ User cancelled purchase');
      } else if (errorCode == PurchasesErrorCode.purchaseNotAllowedError) {
        print('❌ User not allowed to purchase');
      } else if (errorCode == PurchasesErrorCode.productNotAvailableForPurchaseError) {
        print('❌ Product not available for purchase');
      } else {
        print('❌ Purchase error: ${e.message}');
      }
      return false;
    } catch (e) {
      print('❌ Unexpected purchase error: $e');
      return false;
    }
  }

  /// Restore previous purchases
  Future<bool> restorePurchases() async {
    try {
      print('🔄 Restoring purchases...');

      final customerInfo = await Purchases.restorePurchases();
      final hasEntitlement = customerInfo.entitlements.all[_entitlementId]?.isActive ?? false;

      if (hasEntitlement) {
        print('✅ Purchases restored successfully');
        return true;
      } else {
        print('ℹ️ No active purchases to restore');
        return false;
      }
    } catch (e) {
      print('❌ Error restoring purchases: $e');
      return false;
    }
  }

  /// Get subscription details (for display)
  Future<SubscriptionInfo?> getSubscriptionInfo() async {
    try {
      final customerInfo = await Purchases.getCustomerInfo();
      final entitlement = customerInfo.entitlements.all[_entitlementId];

      if (entitlement == null || !entitlement.isActive) {
        return null;
      }

      return SubscriptionInfo(
        isActive: true,
        productId: entitlement.productIdentifier,
        expirationDate: entitlement.expirationDate,
        willRenew: entitlement.willRenew,
      );
    } catch (e) {
      print('❌ Error getting subscription info: $e');
      return null;
    }
  }

  /// Open platform subscription management
  /// User must cancel through App Store/Play Store settings
  Future<void> manageSubscription() async {
    try {
      // This opens the platform's subscription management
      final customerInfo = await Purchases.getCustomerInfo();
      final managementURL = customerInfo.managementURL;

      if (managementURL != null) {
        print('📱 Management URL: $managementURL');
        // You can use url_launcher to open this URL
        // await launchUrl(Uri.parse(managementURL));
      } else {
        print('⚠️ No management URL available');
      }
    } catch (e) {
      print('❌ Error getting management URL: $e');
    }
  }
}

/// Subscription info model
class SubscriptionInfo {
  final bool isActive;
  final String productId;
  final String? expirationDate;
  final bool willRenew;

  SubscriptionInfo({
    required this.isActive,
    required this.productId,
    this.expirationDate,
    required this.willRenew,
  });
}