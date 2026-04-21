class UserModel {
  final String id;
  final String email;
  final String name;
  final String role;
  final String? photoUrl;
  final String? phone;
  final String? address;
  final DateTime createdAt;

  UserModel({
    required this.id,
    required this.email,
    required this.name,
    this.role = 'user',
    this.photoUrl,
    this.phone,
    this.address,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'] ?? '',
      email: map['email'] ?? '',
      name: map['name'] ?? '',
      role: map['role'] ?? 'user',
      photoUrl: map['photoUrl'],
      phone: map['phone'],
      address: map['address'],
      createdAt: map['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['createdAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'role': role,
      'photoUrl': photoUrl,
      'phone': phone,
      'address': address,
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }

  UserModel copyWith({
    String? name,
    String? role,
    String? photoUrl,
    String? phone,
    String? address,
  }) {
    return UserModel(
      id: id,
      email: email,
      name: name ?? this.name,
      role: role ?? this.role,
      photoUrl: photoUrl ?? this.photoUrl,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      createdAt: createdAt,
    );
  }

  bool get isOwner => role == 'owner';
}
