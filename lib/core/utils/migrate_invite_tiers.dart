// ============================================
// FIREBASE MIGRATION SCRIPT
// Run this ONCE to add inviteTier to existing codes
// ============================================

import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> migrateInviteCodeTiers() async {
  final firestore = FirebaseFirestore.instance;

  print('🔄 Starting invite code tier migration...');
  print('');

  try {
    // ============================================
    // STEP 1: Update FOUNDER-8KJ3MP (Tier 0)
    // ============================================
    print('📌 Step 1: Updating FOUNDER-8KJ3MP to Tier 0...');
    await firestore.collection('inviteCodes').doc('FOUNDER-8KJ3MP').update({
      'inviteTier': 0,
      'isFounderCode': true,
    });
    print('✅ FOUNDER-8KJ3MP → Tier 0 (Founder, FREE)');
    print('');

    // ============================================
    // STEP 2: Update YOUR first-gen codes (Tier 1 - FREE)
    // These are Cliff's codes that grant free access
    // ============================================
    print('📌 Step 2: Updating first-generation codes to Tier 1 (FREE)...');
    final cliffCodes = ['INV-MJCRFW', 'INV-HDL44A', 'INV-HVS4BU'];

    for (final code in cliffCodes) {
      await firestore.collection('inviteCodes').doc(code).update({
        'inviteTier': 1,
        'isFounderCode': true,  // ← CRITICAL: Must be true for free access!
      });
      print('✅ $code → Tier 1 (First-gen, FREE)');
    }
    print('');

    // ============================================
    // STEP 3: Update all other codes (Tier 2 - PAID)
    // ============================================
    print('📌 Step 3: Updating remaining codes to Tier 2 (PAID)...');
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

      print('✅ $code → Tier 2 (Paid, \$2/month)');
      updatedCount++;
    }

    print('');
    print('📊 Migration Summary:');
    print('   • Tier 0 (Founder): 1 code');
    print('   • Tier 1 (First-gen, FREE): ${cliffCodes.length} codes');
    print('   • Tier 2 (Paid): $updatedCount codes');
    print('');
    print('🎉 Migration complete!');

  } catch (e) {
    print('❌ Migration failed: $e');
    rethrow;
  }
}

// ============================================
// VERIFICATION SCRIPT
// Run this to verify the migration worked
// ============================================

Future<void> verifyMigration() async {
  final firestore = FirebaseFirestore.instance;

  print('🔍 Verifying migration...');
  print('');

  // Check Founder code
  final founderDoc = await firestore.collection('inviteCodes').doc('FOUNDER-8KJ3MP').get();
  final founderData = founderDoc.data();
  print('FOUNDER-8KJ3MP:');
  print('  inviteTier: ${founderData?['inviteTier']} (expected: 0)');
  print('  isFounderCode: ${founderData?['isFounderCode']} (expected: true)');
  print('');

  // Check first-gen codes
  final firstGenCodes = ['INV-MJCRFW', 'INV-HDL44A', 'INV-HVS4BU'];
  for (final code in firstGenCodes) {
    final doc = await firestore.collection('inviteCodes').doc(code).get();
    final data = doc.data();
    print('$code:');
    print('  inviteTier: ${data?['inviteTier']} (expected: 1)');
    print('  isFounderCode: ${data?['isFounderCode']} (expected: true)');
    print('');
  }

  // Check a random tier-2 code
  final allCodes = await firestore.collection('inviteCodes')
      .where('inviteTier', isEqualTo: 2)
      .limit(1)
      .get();

  if (allCodes.docs.isNotEmpty) {
    final doc = allCodes.docs.first;
    final data = doc.data();
    print('${doc.id} (sample Tier 2):');
    print('  inviteTier: ${data['inviteTier']} (expected: 2)');
    print('  isFounderCode: ${data['isFounderCode']} (expected: false)');
    print('');
  }

  print('✅ Verification complete!');
}
