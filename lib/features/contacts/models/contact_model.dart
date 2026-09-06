// lib/features/contacts/models/contact_model.dart
//
// Networking Contact — added 8/26/26 as part of the "day of the gig" flow
// (see lib/features/day_of/). Someone you meet at a jam or gig: name,
// phone and/or email, and a note of where/when you met them. This is a
// real, standalone address-book entry (not scoped to one gig) — you can
// meet the same person again at a different venue later and it's still
// one record, editable/findable independent of any specific gig. The
// metAt* fields below record where the relationship STARTED, not a
// container it lives inside.
//
// FIX (8/26/26, same day): not every contact is a musician. At a jam,
// most people you're adding are; at a regular paying gig, this doubles as
// a way to build a fan/audience email list, and instrument/style don't
// apply to a fan. isMusician gates that — see day_of_screen.dart's
// _ContactDialog, which hides the style/instrument fields entirely when
// it's off. Existing contacts saved before this field existed have no
// 'isMusician' key; fromJson defaults those to true since every contact
// up to this point was in fact added through the jam-prototype workflow.
//
// Composes the shared Person model (core/models/person_model.dart) for
// name/email/phone/instruments — the same fields BandMember uses — rather
// than duplicating that shape. See person_model.dart's header for why that
// refactor was done as a Dart-level composition rather than a Firestore
// migration. instruments/style stay meaningful only when isMusician is
// true; a fan contact just won't have them set.
//
// Local-only for now, on purpose: unlike venue data or jam attendance,
// contacts are personal — nobody else should ever see them, so there is no
// Firestore mirror here at all (see ContactRepository). deviceContactId is
// reserved, unused, for a later fast-follow that links a Contact to an
// entry in the user's phone Contacts app (Cliff asked for this "eventually
// if not immediately" — keeping the field here now means that doesn't
// require a schema migration later, even though the actual sync isn't
// built yet).

import 'package:the_money_gigs/core/models/person_model.dart';

class Contact {
  final Person person;
  bool isMusician;
  String? style; // genre/style, free text — same precedent as JamSession.style; musicians only
  String? notes;

  // Where/when this contact was first met — optional, since a contact can
  // also be added by hand from a future standalone contacts list with no
  // gig context at all.
  String? metAtVenueName;
  String? metAtPlaceId;
  String? metAtGigId; // the specific jam/gig occurrence id, if any
  DateTime metAtDate;

  // Reserved for a later phone-Contacts sync — not read or written by
  // anything yet.
  String? deviceContactId;

  Contact({
    required this.person,
    this.isMusician = true,
    this.style,
    this.notes,
    this.metAtVenueName,
    this.metAtPlaceId,
    this.metAtGigId,
    DateTime? metAtDate,
    this.deviceContactId,
  }) : metAtDate = metAtDate ?? DateTime.now();

  // ── Convenience forwarding to Person — contact.name instead of
  // contact.person.name everywhere it's used ──────────────────────────────
  String get localId => person.localId;
  String get name => person.name;
  set name(String value) => person.name = value;
  String? get email => person.email;
  set email(String? value) => person.email = value;
  String? get phone => person.phone;
  set phone(String? value) => person.phone = value;
  List<String> get instruments => person.instruments;
  set instruments(List<String> value) => person.instruments = value;

  Contact copyWith({
    String? name,
    String? email,
    String? phone,
    List<String>? instruments,
    bool? isMusician,
    String? style,
    String? notes,
    String? metAtVenueName,
    String? metAtPlaceId,
    String? metAtGigId,
    DateTime? metAtDate,
    String? deviceContactId,
  }) {
    return Contact(
      person: person.copyWith(
        name: name,
        email: email,
        phone: phone,
        instruments: instruments,
      ),
      isMusician: isMusician ?? this.isMusician,
      style: style ?? this.style,
      notes: notes ?? this.notes,
      metAtVenueName: metAtVenueName ?? this.metAtVenueName,
      metAtPlaceId: metAtPlaceId ?? this.metAtPlaceId,
      metAtGigId: metAtGigId ?? this.metAtGigId,
      metAtDate: metAtDate ?? this.metAtDate,
      deviceContactId: deviceContactId ?? this.deviceContactId,
    );
  }

  // Flat JSON — person's fields sit at the top level alongside contact's
  // own, same flattening approach BandMember.toMap() already uses, so this
  // reads naturally as one record in the local 'contacts_list' prefs key.
  Map<String, dynamic> toJson() => {
    ...person.toMap(),
    'isMusician': isMusician,
    'style': style,
    'notes': notes,
    'metAtVenueName': metAtVenueName,
    'metAtPlaceId': metAtPlaceId,
    'metAtGigId': metAtGigId,
    'metAtDate': metAtDate.toIso8601String(),
    'deviceContactId': deviceContactId,
  };

  factory Contact.fromJson(Map<String, dynamic> json) => Contact(
    person: Person.fromMap(json),
    // Missing key = saved before this field existed = added through the
    // jam-prototype workflow, which was musician-only at the time.
    isMusician: json['isMusician'] as bool? ?? true,
    style: json['style'] as String?,
    notes: json['notes'] as String?,
    metAtVenueName: json['metAtVenueName'] as String?,
    metAtPlaceId: json['metAtPlaceId'] as String?,
    metAtGigId: json['metAtGigId'] as String?,
    metAtDate: json['metAtDate'] != null
        ? DateTime.tryParse(json['metAtDate'] as String) ?? DateTime.now()
        : DateTime.now(),
    deviceContactId: json['deviceContactId'] as String?,
  );
}
