// seed-indianapolis-jams.js
//
// One-time seeder: adds real, sourced Indianapolis-area jam sessions / open
// mics to the public `venues` Firestore collection — matching existing
// venues where possible, creating new venue docs where needed.
//
// Run it exactly like seed-nashville-jams.js / cleanup-zero-ratings.js —
// from the folder where serviceAccountKey.json lives:
//
//   GOOGLE_API_KEY=your_maps_api_key node seed-indianapolis-jams.js --dry-run
//   GOOGLE_API_KEY=your_maps_api_key node seed-indianapolis-jams.js
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
//
// COVERAGE NOTE (7/30/26): this first pass covers Indianapolis proper
// (downtown, Broad Ripple, Fountain Square, Castleton) solidly. I could NOT
// find a real, sourced, currently-recurring jam/open mic in the surrounding
// suburbs (Carmel, Fishers, Noblesville, Greenwood, Bloomington) that met
// the same bar as the Nashville list's "confirmed" entries — several leads
// (Musicologie's Carmel-area open mics, Blockhouse Bar in Bloomington,
// Melody Inn's "Open House" night, Zionsville's Village Station Pizza King)
// either had no verifiable day/time, turned out to be a curated concert
// series rather than an open jam, or the venue itself is closed. Rather
// than guess, they're left out. Worth a second pass once Cliff has
// boots-on-the-ground reports from users in those areas.

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
// Sourced from (all checked 7/30/2026):
//   - slipperynoodle.com/indianapolis-the-slippery-noodle-events (venue's own events calendar)
//   - trapindy.com (The Mousetrap Bar & Grill's own site) + do317.com weekly event pages
//   - thejazzkitchen.com (venue's own site) — dedicated Monday Night Jazz Jam page
//   - jazznearyou.com venue profile for Chatterbox Jazz Club (day-level only, no published time)
//   - redliongroghouse.com / Eventbrite recurring listing for Red Lion Grog House
//   - meetup.com/booksnbrewsopenmic (official group page for Books & Brews Mothership)
//
// day must exactly match Dart's DayOfWeek.toString() format, since
// JamSession.fromJson() parses it with a literal string comparison.
// Same for frequency / JamFrequencyType.

const JAM_SESSIONS_TO_SEED = [
  {
    venueName: 'The Slippery Noodle Inn',
    placesQuery: 'The Slippery Noodle Inn, Indianapolis, IN',
    day: 'DayOfWeek.wednesday',
    time: { hour: 20, minute: 0 },
    style: 'Blues Jam',
    sourceUrl: 'https://slipperynoodle.com/indianapolis-the-slippery-noodle-events',
    sourceNote: 'Every Wednesday, back stage. Sign-ups start ~7:30pm, show runs 8:00-11:30pm. ' +
        'Rotating featured host by week of month (1st=Steve Robbins, 2nd=Dennis McClure, ' +
        '3rd=Charlie Cheesman, 4th=Zach Day, 5th=Russ Bucy). Welcoming to veterans and newbies. ' +
        'Indiana\'s oldest continually-operated bar, downtown at 372 S Meridian St.',
    confidence: 'confirmed',
  },
  {
    venueName: 'The Mousetrap Bar & Grill',
    placesQuery: 'The Mousetrap Bar and Grill, Indianapolis, IN',
    day: 'DayOfWeek.wednesday',
    time: { hour: 20, minute: 0 },
    style: 'The Family Jam (all instruments/vocalists)',
    sourceUrl: 'https://trapindy.com/',
    sourceNote: 'Weekly Wednesday jam featuring "Indy\'s best musicians," 8pm. Broad Ripple, ' +
        '5565 N Keystone Ave.',
    confidence: 'confirmed',
  },
  {
    venueName: 'The Mousetrap Bar & Grill',
    placesQuery: 'The Mousetrap Bar and Grill, Indianapolis, IN',
    day: 'DayOfWeek.sunday',
    time: { hour: 20, minute: 0 },
    style: 'Acoustic Bluegrass Open Jam',
    sourceUrl: 'https://trapindy.com/events/acoustic-bluegrass-open-jam-every-sunday/',
    sourceNote: 'EVERY Sunday, 8pm. Hosted by Johnny Plott, Kris Potts, and Scott Nelson ' +
        '(members of The Midwest Rhythm Exchange and Flatland Harmony Experiment). Bring your ' +
        'instrument — described as "not your traditional bluegrass jam." No drums unless asked.',
    confidence: 'confirmed',
  },
  {
    venueName: 'The Jazz Kitchen',
    placesQuery: 'The Jazz Kitchen, Indianapolis, IN',
    day: 'DayOfWeek.monday',
    time: { hour: 20, minute: 0 },
    style: 'Jazz Jam',
    sourceUrl: 'https://thejazzkitchen.com/monday-night-jazz-jam-session/',
    sourceNote: 'Every Monday night, free (no ticket/cover for the jam), 21+. House rhythm ' +
        'section: Kevin Anker (keys), Fred Withrow (bass), Mike Kessler (drums) — sit in or ' +
        'just listen. Broad Ripple, 5377 N College Ave.',
    confidence: 'confirmed',
  },
  {
    venueName: 'Chatterbox Jazz Club',
    placesQuery: 'Chatterbox Jazz Club, Indianapolis, IN',
    day: 'DayOfWeek.monday',
    time: { hour: 20, minute: 0 },
    style: 'Jazz Jam',
    sourceUrl: 'https://www.jazznearyou.com/indianapolis/venue/chatterbox-jazz-club',
    sourceNote: 'Monday and Wednesday are reserved for jazz jams per venue profile — day ' +
        'confirmed across multiple sources, exact start time NOT published (venue open ' +
        '4pm-12am Mon-Thu; 8pm is a placeholder matching typical dive-bar jazz jam start). ' +
        'Downtown, 435 Massachusetts Ave. Confirm time by phone: (317) 636-0584.',
    confidence: 'verify time',
  },
  {
    venueName: 'Chatterbox Jazz Club',
    placesQuery: 'Chatterbox Jazz Club, Indianapolis, IN',
    day: 'DayOfWeek.wednesday',
    time: { hour: 20, minute: 0 },
    style: 'Jazz Jam',
    sourceUrl: 'https://www.jazznearyou.com/indianapolis/venue/chatterbox-jazz-club',
    sourceNote: 'Same as the Monday entry — day confirmed, time is a placeholder. Confirm by ' +
        'phone: (317) 636-0584.',
    confidence: 'verify time',
  },
  {
    venueName: 'Red Lion Grog House',
    placesQuery: 'Red Lion Grog House, Indianapolis, IN',
    day: 'DayOfWeek.wednesday',
    time: { hour: 19, minute: 30 },
    style: 'Open Mic (music, poetry, comedy)',
    sourceUrl: 'https://redliongroghouse.com/indianapolis-fountain-square-red-lion-events',
    sourceNote: 'Every Wednesday, 7:30pm start, recurring on Eventbrite/AllEvents. Fountain ' +
        'Square, Virginia Ave. Mixed-format night — music sits alongside poetry and comedy.',
    confidence: 'confirmed',
  },
  {
    venueName: 'Books & Brews (Mothership)',
    placesQuery: 'Books & Brews Mothership, 9402 Uptown Dr, Indianapolis, IN',
    day: 'DayOfWeek.thursday',
    time: { hour: 19, minute: 0 },
    style: 'Open Mic',
    sourceUrl: 'https://www.meetup.com/booksnbrewsopenmic/',
    sourceNote: 'Every Thursday, 7pm, per venue\'s own recurring Meetup listing (1,900+ ' +
        'members, weekly events scheduled out for months). 3 songs or 15-min set, family ' +
        'friendly. 9402 Uptown Dr Suite 1400 (Castleton area).',
    confidence: 'confirmed',
  },
  {
    venueName: 'Books & Brews (Mothership)',
    placesQuery: 'Books & Brews Mothership, 9402 Uptown Dr, Indianapolis, IN',
    day: 'DayOfWeek.monday',
    time: { hour: 15, minute: 0 },
    style: 'Open Jam',
    sourceUrl: 'https://www.meetup.com/booksnbrewsopenmic/',
    sourceNote: 'Stated directly in the group\'s official description ("Monday afternoon open ' +
        'jam sessions starting at 3pm") but — unlike the Thursday open mic — not shown as an ' +
        'individually dated recurring event on the Meetup calendar. Confirm it\'s still ' +
        'running before treating this as gospel.',
    confidence: 'verify frequency',
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
    // Defaults to weekly unless the entry specifies otherwise.
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
  console.log(isDryRun ? '🔍 DRY RUN — no Firestore writes will be made.\n' : '🔧 Seeding Indianapolis jam sessions...\n');

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
