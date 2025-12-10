// lib/core/services/app_update_service.dart
import 'package:in_app_update/in_app_update.dart';

class AppUpdateService {
  Future<void> checkForUpdate() async {    try {
    final AppUpdateInfo updateInfo = await InAppUpdate.checkForUpdate();

    if (updateInfo.updateAvailability == UpdateAvailability.updateAvailable) {
      // An update is available. Start the flexible update flow.
      final AppUpdateResult appUpdateResult = await InAppUpdate.startFlexibleUpdate();

      if (appUpdateResult == AppUpdateResult.success) {
        // The user has accepted the update.
        // You must now trigger the installation of the downloaded update.
        await InAppUpdate.completeFlexibleUpdate();
      }
    }
  } catch (e) {
    // Handle any errors that might occur during the update process.
    print('Error checking for app update: $e');
  }
  }
}
