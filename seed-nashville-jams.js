// seed-nashville-jams.js
//
// One-time seeder: adds real, sourced Nashville-area jam sessions / open
// mics to the public `venues` Firestore collection — matching existing
// venues where possible, creating new venue docs where needed.
//
// Run it exactly like cleanup-zero-ratings.js — from the folder where
// serviceAccountKey.json lives:
//
//   GOOGLE_API_KEY=your_maps_api_key node seed-nashville-jams.js --dry-run
//   GOOGLE_API_KEY=your_maps_api_key node seed-nashville-jams.js
//
// --dry-run prints every planned create/update WITHOUT touching Firestore
// or spending Places API quota beyond the lookup itself. Always run dry
// first and read the output before running for real.
//
// Requires Node 18+ (uses the built-in fetch). Cliff's functions/package.json
// already targets Node 20, so this should just work in the same environment.
//
// WHAT THIS DOES NOT DO:
//   - It does not verify a jam/open mic is still running tonight. Every
//     entry below has a sourceUrl and sourceNote — spot-check anything
//     you're not sure about before leaning on it in the app.
//   - It does not geocode or write anything if the Places lookup for a
//     venue name comes back empty or ambiguous — those are logged as
//     SKIPPED so nothing gets written with a guessed address.

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();
const isDryRun = process.argv.includes('--dry-run');

const GOOGLE_API_KEY = process.env.GOOGLE_API_KEY;
if (!GOOGLE_API_KEY) {
  console.error(
    '❌ Set GOOGLE_API_KEY in the environment (same Maps API key the app ' +
    'uses) before running this script. It\'s used to resolve each venue\'s ' +
    'real place_id, address, and coordinates.'
  );
  process.exit(1);
}

// ── The list ──────────────────────────────────────────────────────────────
//
// Sourced from:
//   - notesonnashville.com/live-music/weekly-monthly-music-events (updated 6/29/2026)
//   - bluesandroots.org/bluesjams (Nashville Blues & Roots Alliance, live list)
//   - bluebirdcafe.com/calendar
// Every entry lists day/time as published; "confidence: verify" entries had
// a day but no published time on the source page — confirm before treating
// the time as gospel.
//
// day must exactly match Dart's DayOfWeek.toString() format, since
// JamSession.fromJson() parses it with a literal string comparison.
// Same for frequency / JamFrequencyType.

const JAM_SESSIONS_TO_SEED = [
  {
    venueName: 'The Bluebird Cafe',
    placesQuery: 'The Bluebird Cafe, Nashville, TN',
    day: 'DayOfWeek.monday',
    time: { hour: 18, minute: 0 },
    style: 'Open Mic (songwriters)',
    sourceUrl: 'https://bluebirdcafe.com/calendar/',
    sourceNote: 'Doors 5:30pm, show 6pm, online signup opens 11am same day. All ages, $15 F&B minimum.',
    confidence: 'confirmed',
  },
  {
    venueName: 'The Station Inn',
    placesQuery: 'The Station Inn, Nashville, TN',
    day: 'DayOfWeek.sunday',
    time: { hour: 19, minute: 0 },
    style: 'Bluegrass Jam',
    sourceUrl: 'https://stationinn.com/',
    sourceNote: 'No cover. Bring your instrument and sit in — get there early.',
    confidence: 'confirmed',
  },
  {
    venueName: "Rudy's Jazz Room",
    placesQuery: "Rudy's Jazz Room, Nashville, TN",
    day: 'DayOfWeek.sunday',
    time: { hour: 21, minute: 0 },
    style: 'Jazz Jam',
    sourceUrl: 'https://www.rudysjazzroom.com/calendar',
    sourceNote: '$10 admission + $10 F&B minimum. Small room, advance purchase recommended.',
    confidence: 'confirmed',
  },
  {
    venueName: "Bowie's Nashville",
    placesQuery: "Bowie's Nashville, TN",
    day: 'DayOfWeek.wednesday',
    time: { hour: 21, minute: 0 },
    style: 'Open Jam (all instruments/vocalists)',
    sourceUrl: 'https://www.bowiesnashville.com/jam-night',
    sourceNote: 'Open to anyone who plays an instrument or sings. NOTE (7/24/26): ' +
        'venue appears to have rebranded to "Hit Parader" at this same address ' +
        '(174 3rd Ave N) — bowiesnashville.com still advertises this Wednesday ' +
        '9pm jam under the old name. Kept in the seed as-is per Cliff; worth a ' +
        'confirm-by-phone if this one gets flagged by a user later.',
    confidence: 'confirmed',
  },
  {
    venueName: "Papa Turney's BBQ",
    placesQuery: "Papa Turney's BBQ, Nashville, TN",
    day: 'DayOfWeek.wednesday',
    time: { hour: 19, minute: 0 },
    style: 'Open Mic Jam',
    sourceUrl: 'https://papaturneysbbq.com/live-music-nashville',
    sourceNote: '7-9pm.',
    confidence: 'confirmed',
  },
  {
    venueName: "Papa Turney's BBQ",
    placesQuery: "Papa Turney's BBQ, Nashville, TN",
    day: 'DayOfWeek.saturday',
    time: { hour: 18, minute: 0 },
    style: 'Blues Jam',
    sourceUrl: 'https://papaturneysbbq.com/live-music-nashville',
    sourceNote: '6-9pm, family-friendly. Sign up at the door — bring your chops.',
    confidence: 'confirmed',
  },
  {
    venueName: 'Tennessee Brew Works',
    placesQuery: 'Tennessee Brew Works, Nashville, TN',
    day: 'DayOfWeek.monday',
    time: { hour: 18, minute: 0 },
    style: 'Open Mic (originals or covers)',
    sourceUrl: 'https://www.tnbrew.com/livemusic',
    sourceNote: 'Free, relaxed setting for local songwriters.',
    confidence: 'confirmed',
  },
  {
    venueName: 'Marquee Nashville',
    placesQuery: 'Marquee, Nashville, TN',
    day: 'DayOfWeek.thursday',
    time: { hour: 18, minute: 30 },
    style: 'Jazz Jam',
    sourceUrl: 'https://www.marqueenashville.com/entertainment/',
    sourceNote: '6:30-9:30pm.',
    confidence: 'confirmed',
  },

  // ── Day confirmed via Nashville Blues & Roots Alliance; exact time not
  //    published on that page — verify against each venue's own site before
  //    treating the time below as anything but a placeholder guess.
  {
    venueName: 'Bourbon Street Blues & Boogie Bar',
    placesQuery: 'Bourbon Street Blues and Boogie Bar, Nashville, TN',
    day: 'DayOfWeek.monday',
    time: { hour: 21, minute: 0 },
    style: 'Blues Jam',
    sourceUrl: 'https://www.bourbonstreetbluesandboogiebar.com/',
    sourceNote: 'Day per Nashville Blues & Roots Alliance jam list — confirm time on venue site.',
    confidence: 'verify time',
  },
  {
    venueName: "Carol Ann's Home Cooking Cafe",
    placesQuery: "Carol Ann's Home Cooking Cafe, Nashville, TN",
    day: 'DayOfWeek.tuesday',
    time: { hour: 19, minute: 0 },
    style: 'Blues Jam',
    sourceUrl: 'https://carolannsnashville.com/',
    sourceNote: 'Day per Nashville Blues & Roots Alliance jam list — confirm time on venue site.',
    confidence: 'verify time',
  },
  {
    venueName: 'High Society',
    placesQuery: 'High Society, 211 W Main St, Murfreesboro, TN',
    day: 'DayOfWeek.wednesday',
    time: { hour: 19, minute: 0 },
    style: 'Open Jam (blues/rock/Americana/country)',
    sourceUrl: 'https://boropulse.com/2025/12/musicians-converge-at-high-society-for-wednesday-night-jam-with-mickey-gannon-each-week/',
    sourceNote: 'Murfreesboro, not Nashville proper — original "Nashville, TN" Places query matched the wrong business. 7-10pm, hosted by Mickey Gannon, EVERY Wednesday EXCEPT the 1st Wednesday of the month.',
    confidence: 'confirmed',
  },
  {
    venueName: 'Memories Bar and Grill',
    placesQuery: 'Memories Bar and Grill, Nashville, TN',
    day: 'DayOfWeek.thursday',
    time: { hour: 19, minute: 0 },
    style: 'Blues Jam',
    sourceUrl: 'https://memoriesbargrill.com/',
    sourceNote: 'Day per Nashville Blues & Roots Alliance jam list — confirm time on venue site.',
    confidence: 'verify time',
  },
  {
    venueName: 'Elm Hill Tavern',
    placesQuery: 'Elm Hill Tavern, Nashville, TN',
    day: 'DayOfWeek.sunday',
    time: { hour: 19, minute: 0 },
    style: 'Blues Jam',
    sourceUrl: 'https://www.facebook.com/ElmHillTavern',
    sourceNote: 'Day per Nashville Blues & Roots Alliance jam list — confirm time on venue Facebook.',
    confidence: 'verify time',
  },
  {
    venueName: "Dee's Country Cocktail Lounge",
    placesQuery: "Dee's Country Cocktail Lounge, Nashville, TN",
    day: 'DayOfWeek.monday',
    time: { hour: 18, minute: 0 },
    style: 'Bluegrass Jam',
    sourceUrl: 'https://deeslounge.com/shows-events/',
    sourceNote: '6-8pm, typically Kyle Tuttle\'s band, $10 cover. East Nashville.',
    confidence: 'confirmed',
  },
  {
    venueName: '12South Taproom',
    placesQuery: '12South Taproom, Nashville, TN',
    day: 'DayOfWeek.monday',
    time: { hour: 19, minute: 0 },
    style: 'Bluegrass Jam',
    sourceUrl: 'https://www.12southtaproom.com/',
    sourceNote: 'No cover — time approximate, confirm on venue site.',
    confidence: 'verify time',
  },

  // ── Surrounding area (outside Davidson County, still day-trip range) ──
  {
    venueName: 'Hop Springs Beer Park',
    placesQuery: 'Hop Springs Beer Park, Murfreesboro, TN',
    day: 'DayOfWeek.sunday',
    time: { hour: 18, minute: 0 },
    style: 'Jam',
    sourceUrl: 'https://www.hopspringstn.com/',
    sourceNote: 'Murfreesboro, ~35 min from downtown Nashville. Day per Blues & Roots Alliance — confirm time.',
    confidence: 'verify time',
  },
  {
    venueName: 'Twisted Oaks',
    placesQuery: 'Twisted Oaks, Smithville, TN',
    day: 'DayOfWeek.wednesday',
    time: { hour: 18, minute: 0 },
    style: 'Open Mic/Open Jam',
    sourceUrl: null,
    sourceNote: 'Smithville, ~60mi east of Nashville. Found via the venue\'s own Facebook post ' +
        '(7/21/26): "Open Mic/Open Jam every Wednesday at Twisted Oaks in Smithville, TN 6-9. ' +
        'Come out and jam with us." Flagged by Joe Cowels testing the app in the field. ' +
        'Grab the actual FB post URL for the record if this needs re-verifying later.',
    confidence: 'confirmed',
  },
  {
    venueName: "Breeden's Orchard",
    placesQuery: "Breeden's Orchard, Mt. Juliet, TN",
    day: 'DayOfWeek.thursday',
    time: { hour: 19, minute: 0 },
    frequency: 'JamFrequencyType.monthlySameDay',
    nthValue: 4,
    style: "Writer's Round (sign up to play originals)",
    sourceUrl: 'https://www.breedensorchard.com/all-happenings/writersround',
    sourceNote: 'Monthly, not weekly — observed on 6/25/26 and 7/23/26, both the 4th ' +
        'Thursday of the month, 7-9pm. Sign up to play original songs. Venue site notes ' +
        '"more times coming soon," so double-check the pattern holds after a couple more months.',
    confidence: 'confirmed',
  },
  {
    venueName: 'Drifters Tennessee Barbeque',
    placesQuery: 'Drifters Tennessee Barbeque, 1008B Woodland St, Nashville, TN',
    day: 'DayOfWeek.monday',
    time: { hour: 18, minute: 0 },
    style: 'Songwriter Open Mic',
    sourceUrl: null,
    sourceNote: 'Facebook post by Ira Baron (7/19/26): "#songwriter #openmic Monday nights ' +
        'from 6 to 9 at Drifters Tennessee Barbeque. Original, live music at its freshest. ' +
        '1008B Woodland St. E Nashville/5 Points."',
    confidence: 'confirmed',
  },

  // ── "The Get Up" — Savio Productions' rotating weekly songwriter round.
  //    Free to attend, sign up via DM/comment @TheGetUpNashville. Site:
  //    thegetupnashville.com. Schedule below observed for the week of
  //    7/20-7/23/26 via their own promo graphic — venues/days match what
  //    press coverage describes as their standing rotation (Big Shotz on
  //    Mon/Tue/Wed), but reconfirm periodically since rotations like this
  //    sometimes shift.
  {
    venueName: 'Big Shotz',
    placesQuery: 'Big Shotz, Nashville, TN',
    day: 'DayOfWeek.monday',
    time: { hour: 18, minute: 0 },
    style: "The Get Up — Writers Round",
    sourceUrl: 'https://www.thegetupnashville.com/',
    sourceNote: 'Part of a nightly rotating circuit — see other "The Get Up" entries. ' +
        'Observed week of 7/20/26. 6-10pm.',
    confidence: 'confirmed',
  },
  {
    venueName: 'The Stillery Midtown',
    placesQuery: 'The Stillery, Midtown, Nashville, TN',
    day: 'DayOfWeek.monday',
    time: { hour: 18, minute: 0 },
    style: "The Get Up — Writers Round",
    sourceUrl: 'https://www.thegetupnashville.com/',
    sourceNote: 'Part of a nightly rotating circuit — see other "The Get Up" entries. ' +
        'Observed week of 7/20/26. 6-10pm.',
    confidence: 'confirmed',
  },
  {
    venueName: 'Big Shotz',
    placesQuery: 'Big Shotz, Nashville, TN',
    day: 'DayOfWeek.tuesday',
    time: { hour: 18, minute: 0 },
    style: "The Get Up — Writers Round",
    sourceUrl: 'https://www.thegetupnashville.com/',
    sourceNote: 'Part of a nightly rotating circuit — see other "The Get Up" entries. ' +
        'Observed week of 7/20/26. 6-10pm.',
    confidence: 'confirmed',
  },
  {
    venueName: "Pooky Jane's",
    placesQuery: "Pooky Jane's, Nashville, TN",
    day: 'DayOfWeek.tuesday',
    time: { hour: 18, minute: 0 },
    style: "The Get Up — Writers Round",
    sourceUrl: 'https://www.thegetupnashville.com/',
    sourceNote: 'Part of a nightly rotating circuit — see other "The Get Up" entries. ' +
        'Observed week of 7/20/26. 6-10pm.',
    confidence: 'confirmed',
  },
  {
    venueName: 'Big Shotz',
    placesQuery: 'Big Shotz, Nashville, TN',
    day: 'DayOfWeek.wednesday',
    time: { hour: 18, minute: 0 },
    style: "The Get Up — Writers Round",
    sourceUrl: 'https://www.thegetupnashville.com/',
    sourceNote: 'Part of a nightly rotating circuit — see other "The Get Up" entries. ' +
        'Observed week of 7/20/26. 6-10pm.',
    confidence: 'confirmed',
  },
  {
    venueName: 'The Rusty Nail',
    placesQuery: 'The Rusty Nail, Nashville, TN',
    day: 'DayOfWeek.wednesday',
    time: { hour: 18, minute: 0 },
    style: "The Get Up — Writers Round",
    sourceUrl: 'https://www.thegetupnashville.com/',
    sourceNote: 'Part of a nightly rotating circuit — see other "The Get Up" entries. ' +
        'Observed week of 7/20/26. 6-10pm. Double-check Places match lands in Nashville, ' +
        'not a same-named bar elsewhere in TN.',
    confidence: 'verify time',
  },
  {
    venueName: 'The Nash',
    placesQuery: 'The Nash, Nashville, TN',
    day: 'DayOfWeek.thursday',
    time: { hour: 16, minute: 0 },
    style: "The Get Up — Writers Round",
    sourceUrl: 'https://www.thegetupnashville.com/',
    sourceNote: 'Part of a nightly rotating circuit — see other "The Get Up" entries. ' +
        'Observed week of 7/20/26. 4-8pm.',
    confidence: 'confirmed',
  },

  {
    venueName: 'The Cookery',
    placesQuery: 'The Cookery, 1827 12th Ave S, Nashville, TN',
    day: 'DayOfWeek.saturday',
    time: { hour: 18, minute: 0 },
    frequency: 'JamFrequencyType.monthlySameDay',
    nthValue: 3,
    style: 'Open Heart Night — Open Mic (community/faith-oriented)',
    sourceUrl: null,
    sourceNote: 'Flyer for "Open Heart Night," 7/18/26 @ 6pm, "Monthly Open Mic Night for ' +
        'Believers in Nashville," 1827 12th Ave S. Only ONE date observed — the 3rd-Saturday ' +
        'pattern is a guess from that single data point, unlike Breeden\'s (2 data points). ' +
        'Confirm the next occurrence before trusting this cadence.',
    confidence: 'verify frequency',
  },

  {
    venueName: 'Stoke Haus Brewing & Barbecue',
    placesQuery: 'Stoke Haus Brewing & Barbecue, 948 Main St, Nashville, TN',
    day: 'DayOfWeek.wednesday',
    time: { hour: 18, minute: 0 },
    style: "Writer's Open Mic (hosted by Doc Downs)",
    sourceUrl: null,
    sourceNote: 'Facebook post by Doc Downs (7/14/26): "I\'ll be hosting a new writer\'s ' +
        'open mic at Stoke Haus on Main Street starting next Wednesday, 7/22, 6pm! Deets ' +
        'coming soon!" Brand new as of this writing — only the kickoff date is confirmed, ' +
        'treated as weekly since that\'s how hosted open mics normally run. Worth a ' +
        'reconfirm in a few weeks once it has a track record.',
    confidence: 'verify frequency',
  },
  {
    venueName: "Happy's Sports Lounge",
    placesQuery: "Happy's Sports Lounge, 302 West Main St, Murfreesboro, TN",
    day: 'DayOfWeek.wednesday',
    time: { hour: 19, minute: 0 },
    style: 'Musicians Hang / Jam (build-your-own-band format)',
    sourceUrl: 'https://www.happystn.com/events',
    sourceNote: 'Facebook post by Alan Baker (7/14/26) describing the weekly Wed jam: ' +
        'featured artists kick off with a short set, then attendees build their own bands ' +
        'to sit in with. Independently confirmed as a standing weekly event ("Wednesday ' +
        'Night Jam & Musicians Hang") on the venue\'s own site. 7-10pm.',
    confidence: 'confirmed',
  },
];

// ── Google Places lookup ────────────────────────────────────────────────

async function findPlace(query) {
  const url = new URL('https://maps.googleapis.com/maps/api/place/findplacefromtext/json');
  url.searchParams.set('input', query);
  url.searchParams.set('inputtype', 'textquery');
  url.searchParams.set('fields', 'place_id,formatted_address,name,geometry');
  url.searchParams.set('key', GOOGLE_API_KEY);

  const res = await fetch(url.toString());
  const data = await res.json();

  if (data.status !== 'OK' || !data.candidates || data.candidates.length === 0) {
    return null;
  }
  const c = data.candidates[0];
  return {
    placeId: c.place_id,
    name: c.name,
    address: c.formatted_address,
    lat: c.geometry.location.lat,
    lng: c.geometry.location.lng,
  };
}

function buildJamSessionJson(entry, index) {
  return {
    id: `seed_${entry.day.split('.').pop()}_${index}_${Date.now()}`,
    style: entry.style,
    day: entry.day,
    time: { hour: entry.time.hour, minute: entry.time.minute },
    // Defaults to weekly unless the entry specifies otherwise (e.g. a
    // monthly Writer's Round on the "4th Thursday").
    frequency: entry.frequency || 'JamFrequencyType.weekly',
    nthValue: entry.nthValue ?? null,
    showInGigsList: false,
  };
}

// Two jam sessions are "the same" if they land on the same day at the same
// time — used to avoid double-adding on re-runs.
function isSameSession(a, b) {
  return a.day === b.day && a.time?.hour === b.time?.hour && a.time?.minute === b.time?.minute;
}

async function run() {
  console.log(isDryRun ? '🔍 DRY RUN — no Firestore writes will be made.\n' : '🔧 Seeding Nashville jam sessions...\n');

  let created = 0;
  let updated = 0;
  let skippedNoMatch = 0;
  let skippedDuplicate = 0;

  for (let i = 0; i < JAM_SESSIONS_TO_SEED.length; i++) {
    const entry = JAM_SESSIONS_TO_SEED[i];
    console.log(`\n— ${entry.venueName} (${entry.day.split('.').pop()}, ${entry.style}) —`);
    console.log(`  confidence: ${entry.confidence}  source: ${entry.sourceUrl}`);

    const place = await findPlace(entry.placesQuery);
    if (!place) {
      console.log(`  ⚠️  SKIPPED — Places lookup found nothing for "${entry.placesQuery}".`);
      skippedNoMatch++;
      continue;
    }

    console.log(`  📍 Resolved: ${place.name} — ${place.address} (${place.placeId})`);

    const venueRef = db.collection('venues').doc(place.placeId);
    const doc = await venueRef.get();
    const newSession = buildJamSessionJson(entry, i);

    if (doc.exists) {
      const existing = doc.data();
      const existingSessions = existing.jamSessions || [];
      const alreadyThere = existingSessions.some((s) => isSameSession(s, newSession));

      if (alreadyThere) {
        console.log('  ↷ SKIPPED — this venue already has a jam session at this day/time.');
        skippedDuplicate++;
        continue;
      }

      const merged = [...existingSessions, newSession];
      console.log(`  ✏️  UPDATE existing venue — appending jam session (${existingSessions.length} → ${merged.length}).`);
      if (!isDryRun) {
        await venueRef.update({
          jamSessions: merged,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
      updated++;
    } else {
      console.log('  ✨ CREATE new venue with this jam session.');
      if (!isDryRun) {
        await venueRef.set({
          name: place.name,
          address: place.address,
          coordinates: new admin.firestore.GeoPoint(place.lat, place.lng),
          placeId: place.placeId,
          jamSessions: [newSession],
          averageRating: 0.0,
          totalRatings: 0,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          createdBy: 'cliff_seed_script',
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
      created++;
    }
  }

  console.log('\n──────────────────────────────────────────');
  console.log(`Venues created:        ${created}`);
  console.log(`Venues updated:        ${updated}`);
  console.log(`Skipped (no match):    ${skippedNoMatch}`);
  console.log(`Skipped (duplicate):   ${skippedDuplicate}`);
  if (isDryRun) {
    console.log('\nRe-run without --dry-run to apply these changes.');
  }
  process.exit(0);
}

run().catch((e) => {
  console.error('❌ Fatal error:', e);
  process.exit(1);
});
