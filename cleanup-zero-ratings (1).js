// cleanup-zero-ratings.js
//
// Finds every venueRatings document with rating == 0, deletes them,
// and recalculates averageRating + totalRatings for every affected venue.
//
// Run from your moneygigs-export folder (where serviceAccountKey.json lives):
//   node cleanup-zero-ratings.js
//
// Add --dry-run to preview what would be deleted without making changes:
//   node cleanup-zero-ratings.js --dry-run

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();
const isDryRun = process.argv.includes('--dry-run');

async function cleanup() {
  console.log(isDryRun ? '🔍 DRY RUN — no changes will be made.\n' : '🔧 Running cleanup...\n');

  // ── Step 1: Find all zero-rating documents ────────────────────────────────
  const zeroSnapshot = await db
    .collection('venueRatings')
    .where('rating', '==', 0)
    .get();

  if (zeroSnapshot.empty) {
    console.log('✅ No zero-rating documents found. Database is clean.');
    process.exit(0);
  }

  console.log(`Found ${zeroSnapshot.docs.length} zero-rating document(s):\n`);

  const affectedPlaceIds = new Set();

  for (const doc of zeroSnapshot.docs) {
    const d = doc.data();
    console.log(`  DELETE  ${doc.id}`);
    console.log(`          placeId: ${d.placeId}  userId: ${d.userId}  updatedAt: ${d.updatedAt?.toDate?.() ?? 'unknown'}`);
    affectedPlaceIds.add(d.placeId);
  }

  if (isDryRun) {
    console.log(`\n↳ ${zeroSnapshot.docs.length} doc(s) would be deleted across ${affectedPlaceIds.size} venue(s).`);
    console.log('  Re-run without --dry-run to apply.');
    process.exit(0);
  }

  // ── Step 2: Delete in batches of 500 (Firestore batch limit) ─────────────
  const chunks = [];
  const docs = zeroSnapshot.docs;
  for (let i = 0; i < docs.length; i += 500) {
    chunks.push(docs.slice(i, i + 500));
  }

  for (const chunk of chunks) {
    const batch = db.batch();
    for (const doc of chunk) batch.delete(doc.ref);
    await batch.commit();
  }

  console.log(`\n✅ Deleted ${zeroSnapshot.docs.length} zero-rating document(s).`);

  // ── Step 3: Recalculate averageRating + totalRatings for each venue ───────
  console.log('\nRecalculating venue averages...\n');

  for (const placeId of affectedPlaceIds) {
    const validSnapshot = await db
      .collection('venueRatings')
      .where('placeId', '==', placeId)
      .where('rating', '>', 0)
      .get();

    const validRatings = validSnapshot.docs.map(d => d.data().rating);
    const total = validRatings.length;
    const average = total > 0
      ? validRatings.reduce((sum, r) => sum + r, 0) / total
      : 0.0;

    await db.collection('venues').doc(placeId).update({
      averageRating: average,
      totalRatings: total,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log(`  ✅ ${placeId}`);
    console.log(`     averageRating: ${average.toFixed(4)}  totalRatings: ${total}`);
  }

  console.log('\n🎉 Cleanup complete. All affected venues recalculated.');
}

cleanup()
  .catch((err) => {
    console.error('❌ Cleanup failed:', err);
    process.exit(1);
  })
  .finally(() => process.exit(0));
