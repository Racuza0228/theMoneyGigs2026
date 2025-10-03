// lib/venue_contact.dart

class VenueContact {
  final String name;
  final String phone;
  final String email;

  // Constructor with default empty strings for safety
  const VenueContact({
    this.name = '',
    this.phone = '',
    this.email = '',
  });

  // A convenience getter to check if any contact info has been entered.
  bool get isNotEmpty => name.isNotEmpty || phone.isNotEmpty || email.isNotEmpty;

  // Converts a VenueContact instance to a JSON map.
  Map<String, dynamic> toJson() => {
    'name': name,
    'phone': phone,
    'email': email,
  };

  // Creates a VenueContact instance from a JSON map.
  factory VenueContact.fromJson(Map<String, dynamic> json) {
    return VenueContact(
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      email: json['email'] as String? ?? '',
    );
  }

  // Creates a copy of the instance with optional new values.
  VenueContact copyWith({
    String? name,
    String? phone,
    String? email,
  }) {
    return VenueContact(
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
    );
  }

  // Override `toString` for easy debugging.
  @override
  String toString() {
    return 'VenueContact(name: $name, phone: $phone, email: $email)';
  }

  // Override `==` and `hashCode` for proper object comparison.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is VenueContact &&
              runtimeType == other.runtimeType &&
              name == other.name &&
              phone == other.phone &&
              email == other.email;

  @override
  int get hashCode => name.hashCode ^ phone.hashCode ^ email.hashCode;
}
