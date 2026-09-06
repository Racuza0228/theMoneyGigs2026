// lib/core/models/person_model.dart
//
// Shared identity fields for "a musician you know" — added 8/26/26 as the
// common base underneath both BandMember (features/bands/models/band_model
// .dart) and the new networking Contact (features/contacts/models/
// contact_model.dart), instead of the two maintaining separate, drifting
// copies of name/email/phone/instruments.
//
// Deliberately NOT the JSON shape either of those two write to storage —
// BandMember flattens these same fields back out to the exact top-level
// Firestore keys it always has ('name', 'email', 'phone', 'instruments'),
// so existing live band documents need zero migration. Person exists at
// the Dart level for shared fields/logic, not as a nested serialized
// object. See the FIX note at the top of band_model.dart's BandMember class
// for the full reasoning.
//
// email is nullable here even though BandMember requires one (band invites
// go out by email) — that requirement is BandMember's own business rule,
// enforced in its constructor, not something every kind of Person needs.
// A jam/gig Contact only needs a name; phone and/or email are optional.

class Person {
  final String localId; // client-generated UUID, stable reference
  String name;
  String? email;
  String? phone;
  List<String> instruments;

  Person({
    required this.localId,
    required this.name,
    this.email,
    this.phone,
    this.instruments = const [],
  });

  Person copyWith({
    String? name,
    String? email,
    String? phone,
    List<String>? instruments,
  }) {
    return Person(
      localId: localId,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      instruments: instruments ?? this.instruments,
    );
  }

  Map<String, dynamic> toMap() => {
    'localId': localId,
    'name': name,
    'email': email,
    'phone': phone,
    'instruments': instruments,
  };

  factory Person.fromMap(Map<String, dynamic> map) => Person(
    localId: map['localId'] as String,
    name: map['name'] as String? ?? '',
    email: map['email'] as String?,
    phone: map['phone'] as String?,
    instruments: (map['instruments'] as List?)?.cast<String>() ?? [],
  );
}
