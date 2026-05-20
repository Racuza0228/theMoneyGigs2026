// lib/core/services/subscription_service.dart
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:flutter/services.dart'; // ← ADD THIS for PlatformException
import 'package:the_money_gigs/core/utils/logger.dart';

class SubscriptionService {
  static const String _entitlementId = 'network_access';
  static const String _monthlyProductId = 'moneygigs_network_monthly';

  /// Check if user has active subscription
  Future<bool> hasActiveSubscription() async {
    try {
      final customerInfo = await Purchases.getCustomerInfo();

      // Check if user has the network_access entitlement
      final hasEntitlement = customerInfo.entitlements.all[_entitlementId]?.isActive ?? false;

      log('📊 Subscription status: ${hasEntitlement ? "ACTIVE" : "INACTIVE"}');
      return hasEntitlement;
    } catch (e) {
      log('❌ Error checking subscription: $e');
      return false;
    }
  }

  /// Get available subscription products
  Future<List<StoreProduct>> getProducts() async {
    try {
      final offerings = await Purchases.getOfferings();

      if (offerings.current == null) {
        log('⚠️ No offerings configured in RevenueCat');
        return [];
      }

      final products = offerings.current!.availablePackages
          .map((package) => package.storeProduct)
          .toList();

      log('📦 Found ${products.length} products');
      return products;
    } catch (e) {
      log('❌ Error fetching products: $e');
      return [];
    }
  }


  /// Purchase monthly subscription
  Future<bool> purchaseMonthlySubscription() async {
    try {
      log('💳 Starting purchase...');

      // Get offerings
      final offerings = await Purchases.getOfferings();
      if (offerings.current == null) {
        log('❌ No offerings available');
        return false;
      }

      // Find the monthly package
      final package = offerings.current!.monthly;
      if (package == null) {
        log('❌ Monthly package not found in offerings');
        // Check what packages ARE available
        final available = offerings.current!.availablePackages;
        log('📦 Available packages: ${available.map((p) => p.identifier).toList()}');
        return false;
      }

      log('💳 Purchasing package: ${package.identifier}');

      // Make purchase - returns CustomerInfo now, not PurchaseResult
      final purchaseResult = await Purchases.purchasePackage(package);

      // Get customer info from result
      final customerInfo = purchaseResult.customerInfo;

      // Check if purchase was successful
      final hasEntitlement = customerInfo.entitlements.all[_entitlementId]?.isActive ?? false;

      if (hasEntitlement) {
        log('✅ Purchase successful!');
        return true;
      } else {
        log('⚠️ Purchase completed but entitlement not active');
        return false;
      }

    } on PlatformException catch (e) {
      final errorCode = PurchasesErrorHelper.getErrorCode(e);

      if (errorCode == PurchasesErrorCode.purchaseCancelledError) {
        log('ℹ️ User cancelled purchase');
      } else if (errorCode == PurchasesErrorCode.purchaseNotAllowedError) {
        log('❌ User not allowed to purchase');
      } else if (errorCode == PurchasesErrorCode.productNotAvailableForPurchaseError) {
        log('❌ Product not available for purchase');
      } else {
        log('❌ Purchase error: ${e.message}');
      }
      return false;
    } catch (e) {
      log('❌ Unexpected purchase error: $e');
      return false;
    }
  }

  /// Restore previous purchases
  Future<bool> restorePurchases() async {
    try {
      log('🔄 Restoring purchases...');

      final customerInfo = await Purchases.restorePurchases();
      final hasEntitlement = customerInfo.entitlements.all[_entitlementId]?.isActive ?? false;

      if (hasEntitlement) {
        log('✅ Purchases restored successfully');
        return true;
      } else {
        log('ℹ️ No active purchases to restore');
        return false;
      }
    } catch (e) {
      log('❌ Error restoring purchases: $e');
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
      log('❌ Error getting subscription info: $e');
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
        log('📱 Management URL: $managementURL');
        // You can use url_launcher to open this URL
        // await launchUrl(Uri.parse(managementURL));
      } else {
        log('⚠️ No management URL available');
      }
    } catch (e) {
      log('❌ Error getting management URL: $e');
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