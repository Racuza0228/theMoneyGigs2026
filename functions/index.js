// functions/index.js
//
// Band/Project Expansion v3.0.0 — Sprint Task 9
//
// Fires when the Flutter app writes a doc to bands/{bandId}/gigNotifications
// (see BandRepository.notifyBandOfGig in lib/features/bands/repositories/
// band_repository.dart, Task 8). This function does NOT send email itself —
// per Cliff's decision (7/20), we're using the official Firebase Extension
// "Trigger Email from Firestore" (firestore-send-email) instead of writing
// custom SendGrid/Mailgun API calls. All this function does is:
//   1. Figure out who should be emailed and with which of the two templates
//      (spec 7.2 — "already in the app" vs "not in the app yet").
//   2. Write one doc per recipient into the `mail` collection, in the exact
//      shape the extension expects.
// The extension (once installed) watches `mail` and does the actual send.
//
// ── ONE-TIME SETUP CLIFF STILL NEEDS TO DO (cannot be done from code) ──────
// 1. Firebase Console → Build → Extensions → install "Trigger Email from
//    Firestore" (publisher: firebase, id: firestore-send-email).
// 2. During install, set:
//      - Collection path: mail
//      - SMTP connection URI: needs a real SMTP account (SendGrid, Mailgun,
//        Postmark, etc. all work — free tier is fine at this volume).
//      - Default FROM address: e.g. "MoneyGigs <noreply@themoneygigs.com>"
//        (needs to be a domain/address the SMTP provider lets you send as).
// 3. Deploy this functions/ folder: `firebase deploy --only functions`
//    (requires `firebase login` + `firebase use moneygigs-cf2c5` once,
//    from a machine with the Firebase CLI and Node 20 installed — this
//    sandbox has neither, so deploy has to happen from Cliff's machine).
//
// Nothing above blocks Task 10 (demo prep) from testing the rest of the app
// — it only blocks actual emails going out. Until the extension is
// installed, docs will just pile up unsent in `mail`, harmlessly.

const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

initializeApp();
const db = getFirestore();

const APP_NAME = 'MoneyGigs';
const FOUNDER_INVITE_URL = 'https://themoneygigs.com'; // real domain, verified via Cliff 7/21

/**
 * @param {Object} p
 * @param {string} p.bandName
 * @param {string} p.venueName
 * @param {Date} p.dateTime
 * @param {number} p.pay
 * @param {string} p.address
 */
function formatGigLine({ bandName, venueName, dateTime, pay, address }) {
  const dateStr = dateTime.toLocaleDateString('en-US', {
    weekday: 'long',
    month: 'long',
    day: 'numeric',
  });
  const timeStr = dateTime.toLocaleTimeString('en-US', {
    hour: 'numeric',
    minute: '2-digit',
  });
  const payStr = `$${pay.toFixed(2)}`;
  return { dateStr, timeStr, payStr, bandName, venueName, address };
}

/** Template A — recipient already has the app (member.status === 'active'). */
function buildActiveMemberEmail({ memberName, gig }) {
  const subject = `${gig.bandName}: new gig at ${gig.venueName} — ${gig.dateStr}`;
  const text =
    `Hey ${memberName || 'there'},\n\n` +
    `${gig.bandName} just got booked:\n\n` +
    `${gig.venueName}\n${gig.address}\n${gig.dateStr} at ${gig.timeStr}\nPay: ${gig.payStr}\n\n` +
    `Open MoneyGigs to see the full details.\n\n— ${APP_NAME}`;
  const html =
    `<p>Hey ${memberName || 'there'},</p>` +
    `<p><strong>${gig.bandName}</strong> just got booked:</p>` +
    `<p><strong>${gig.venueName}</strong><br>${gig.address}<br>` +
    `${gig.dateStr} at ${gig.timeStr}<br>Pay: ${gig.payStr}</p>` +
    `<p>Open MoneyGigs to see the full details.</p>` +
    `<p>— ${APP_NAME}</p>`;
  return { subject, text, html };
}

/**
 * Template B — recipient is not an app user yet (member.status === 'invited').
 * Includes an invite code only if one hasn't already been sent to them
 * (idempotency — see caller).
 */
function buildInvitedMemberEmail({ memberName, gig, inviteCode }) {
  const subject = `${gig.bandName} added you on MoneyGigs — new gig at ${gig.venueName}`;
  const codeLine = inviteCode
    ? `\n\nYour invite code: ${inviteCode}\n${FOUNDER_INVITE_URL}`
    : '';
  const codeHtml = inviteCode
    ? `<p>Your invite code: <strong>${inviteCode}</strong><br><a href="${FOUNDER_INVITE_URL}">${FOUNDER_INVITE_URL}</a></p>`
    : '';
  const text =
    `Hey ${memberName || 'there'},\n\n` +
    `You've been added to ${gig.bandName} on MoneyGigs — an app for tracking gigs and pay.\n\n` +
    `Their next gig:\n${gig.venueName}\n${gig.address}\n${gig.dateStr} at ${gig.timeStr}\nPay: ${gig.payStr}` +
    `${codeLine}\n\n— ${APP_NAME}`;
  const html =
    `<p>Hey ${memberName || 'there'},</p>` +
    `<p>You've been added to <strong>${gig.bandName}</strong> on MoneyGigs — an app for tracking gigs and pay.</p>` +
    `<p>Their next gig:</p>` +
    `<p><strong>${gig.venueName}</strong><br>${gig.address}<br>` +
    `${gig.dateStr} at ${gig.timeStr}<br>Pay: ${gig.payStr}</p>` +
    `${codeHtml}` +
    `<p>— ${APP_NAME}</p>`;
  return { subject, text, html };
}

/**
 * Finds the first invite code in `codes` that still has uses left. Mirrors
 * InviteCode.isAvailable (timesUsed < maxUses) from
 * lib/core/services/network_service.dart — kept as a plain read here since
 * this is a one-off lookup, not worth its own repository class.
 */
async function findAvailableInviteCode(codes) {
  for (const code of codes || []) {
    const doc = await db.collection('inviteCodes').doc(code).get();
    if (!doc.exists) continue;
    const data = doc.data();
    const maxUses = data.maxUses ?? 50;
    const timesUsed = data.timesUsed ?? 0;
    if (timesUsed < maxUses) return code;
  }
  return null;
}

exports.onGigNotificationCreated = onDocumentCreated(
  'bands/{bandId}/gigNotifications/{notificationId}',
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const { bandId } = event.params;
    const notification = snap.data();

    const bandDoc = await db.collection('bands').doc(bandId).get();
    if (!bandDoc.exists) {
      console.error(`Band ${bandId} not found for notification ${event.params.notificationId}`);
      return;
    }
    const band = bandDoc.data();
    const members = band.members || [];

    const gig = formatGigLine({
      bandName: band.name,
      venueName: notification.venueName,
      dateTime: notification.dateTime.toDate(),
      pay: notification.pay,
      address: notification.address,
    });

    // The leader triggered this by booking the gig — they already know.
    // Only the other members need the email.
    const recipients = members.filter((m) => m.email && band.leaderId !== m.networkMemberId);

    // Leader's spare invite codes, fetched once and reused across whichever
    // invited members need one this round (spec 7.2's "pull from leader's
    // myInviteCodes"). NOTE: inviteCodeSent on BandMember (see band_model.dart)
    // stores the CODE STRING itself, not a boolean — the field name is a bit
    // misleading but matches the Dart model, so this function must too.
    let leaderCodes = null;
    const codeByLocalId = {}; // localId -> code string, for the write-back below

    for (const member of recipients) {
      const mail = { to: [member.email], message: null };

      if (member.status === 'active' && member.networkMemberId) {
        mail.message = buildActiveMemberEmail({ memberName: member.name, gig });
      } else {
        // inviteCodeSent already holds a code string if one was sent before —
        // reuse it instead of look up + assign again.
        let inviteCode = member.inviteCodeSent || null;
        if (!inviteCode) {
          if (leaderCodes === null) {
            const leaderDoc = await db.collection('networkMembers').doc(band.leaderId).get();
            leaderCodes = leaderDoc.exists ? leaderDoc.data().myInviteCodes || [] : [];
          }
          inviteCode = await findAvailableInviteCode(leaderCodes);
          if (inviteCode) {
            codeByLocalId[member.localId] = inviteCode;
          }
        }
        mail.message = buildInvitedMemberEmail({ memberName: member.name, gig, inviteCode });
      }

      await db.collection('mail').add(mail);
    }

    // Persist the codes we just assigned, in one read-modify-write on the
    // whole members[] array — same pattern as BandRepository._writeMembers
    // in the Flutter app, so a partial member update can never drift the
    // array (or the memberEmails/memberNetworkIds arrays, untouched here).
    const assignedLocalIds = Object.keys(codeByLocalId);
    if (assignedLocalIds.length > 0) {
      const updatedMembers = members.map((m) =>
        codeByLocalId[m.localId] ? { ...m, inviteCodeSent: codeByLocalId[m.localId] } : m
      );
      await db.collection('bands').doc(bandId).update({
        members: updatedMembers,
        updatedAt: FieldValue.serverTimestamp(),
      });
    }

    console.log(
      `Gig-notification emails queued: band ${bandId}, ${recipients.length} recipient(s).`
    );
  }
);
