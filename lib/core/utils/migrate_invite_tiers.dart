// ============================================
// FIREBASE MIGRATION SCRIPT
// Run this ONCE to add inviteTier to existing codes
// ============================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:the_money_gigs/core/utils/logger.dart';

Future<void> migrateInviteCodeTiers() async {
  final firestore = FirebaseFirestore.instance;

  log('🔄 Starting invite code tier migration...');
  log('');

  try {
    // ============================================
    // STEP 1: Update FOUNDER-8KJ3MP (Tier 0)
    // ============================================
    log('📌 Step 1: Updating FOUNDER-8KJ3MP to Tier 0...');
    await firestore.collection('inviteCodes').doc('FOUNDER-8KJ3MP').update({
      'inviteTier': 0,
      'isFounderCode': true,
    });
    log('✅ FOUNDER-8KJ3MP → Tier 0 (Founder, FREE)');
    log('');

    // ============================================
    // STEP 2: Update YOUR first-gen codes (Tier 1 - FREE)
    // These are Cliff's codes that grant free access
    // ============================================
    log('📌 Step 2: Updating first-generation codes to Tier 1 (FREE)...');
    final cliffCodes = ['INV-MJCRFW', 'INV-HDL44A', 'INV-HVS4BU'];

    for (final code in cliffCodes) {
      await firestore.collection('inviteCodes').doc(code).update({
        'inviteTier': 1,
        'isFounderCode': true,  // ← CRITICAL: Must be true for free access!
      });
      log('✅ $code → Tier 1 (First-gen, FREE)');
    }
    log('');

    // ============================================
    // STEP 3: Update all other codes (Tier 2 - PAID)
    // ============================================
    log('📌 Step 3: Updating remaining codes to Tier 2 (PAID)...');
    final allCodesQuery = await firestore.collection('inviteCodes').get();

    int updatedCount = 0;
    for (final doc in allCodesQuery.docs) {
      final code = doc.id;

      // Skip already-processed codes
      if (code == 'FOUNDER-8KJ3MP' || cliffCodes.contains(code)) {
        continue;
      }

      // Update to Tier 2 (paid)
      await doc.reference.update({
        'inviteTier': 2,
        'isFounderCode': false,  // ← Must be false (requires subscription)
      });

      log('✅ $code → Tier 2 (Paid, \$2/month)');
      updatedCount++;
    }

    log('');
    log('📊 Migration Summary:');
    log('   • Tier 0 (Founder): 1 code');
    log('   • Tier 1 (First-gen, FREE): ${cliffCodes.length} codes');
    log('   • Tier 2 (Paid): $updatedCount codes');
    log('');
    log('🎉 Migration complete!');

  } catch (e) {
    log('❌ Migration failed: $e');
    rethrow;
  }
}

// ============================================
// VERIFICATION SCRIPT
// Run this to verify the migration worked
// ============================================

Future<void> verifyMigration() async {
  final firestore = FirebaseFirestore.instance;

  log('🔍 Verifying migration...');
  log('');

  // Check Founder code
  final founderDoc = await firestore.collection('inviteCodes').doc('FOUNDER-8KJ3MP').get();
  final founderData = founderDoc.data();
  log('FOUNDER-8KJ3MP:');
  log('  inviteTier: ${founderData?['inviteTier']} (expected: 0)');
  log('  isFounderCode: ${founderData?['isFounderCode']} (expected: true)');
  log('');

  // Check first-gen codes
  final firstGenCodes = ['INV-MJCRFW', 'INV-HDL44A', 'INV-HVS4BU'];
  for (final code in firstGenCodes) {
    final doc = await firestore.collection('inviteCodes').doc(code).get();
    final data = doc.data();
    log('$code:');
    log('  inviteTier: ${data?['inviteTier']} (expected: 1)');
    log('  isFounderCode: ${data?['isFounderCode']} (expected: true)');
    log('');
  }

  // Check a random tier-2 code
  final allCodes = await firestore.collection('inviteCodes')
      .where('inviteTier', isEqualTo: 2)
      .limit(1)
      .get();

  if (allCodes.docs.isNotEmpty) {
    final doc = allCodes.docs.first;
    final data = doc.data();
    log('${doc.id} (sample Tier 2):');
    log('  inviteTier: ${data['inviteTier']} (expected: 2)');
    log('  isFounderCode: ${data['isFounderCode']} (expected: false)');
    log('');
  }

  log('✅ Verification complete!');
}
