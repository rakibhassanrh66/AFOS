class PropertyModel {
  final String id;
  final String ownerId;
  final String title;
  final String description;
  final double price;
  final String location;
  final String address;
  final int bedrooms;
  final int bathrooms;
  final double area;
  final List<String> images;
  final List<String> amenities;
  final bool isAvailable;
  final DateTime createdAt;
  final String propertyType;

  PropertyModel({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.description,
    required this.price,
    required this.location,
    required this.address,
    required this.bedrooms,
    required this.bathrooms,
    required this.area,
    required this.images,
    required this.amenities,
    this.isAvailable = true,
    required this.createdAt,
    required this.propertyType,
  });

  factory PropertyModel.fromMap(Map<String, dynamic> map) {
    return PropertyModel(
      id: map['id'] ?? '',
      ownerId: map['ownerId'] ?? '',
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      price: (map['price'] ?? 0).toDouble(),
      location: map['location'] ?? '',
      address: map['address'] ?? '',
      bedrooms: map['bedrooms'] ?? 0,
      bathrooms: map['bathrooms'] ?? 0,
      area: (map['area'] ?? 0).toDouble(),
      images: List<String>.from(map['images'] ?? []),
      amenities: List<String>.from(map['amenities'] ?? []),
      isAvailable: map['isAvailable'] ?? true,
      createdAt: map['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['createdAt'])
          : DateTime.now(),
      propertyType: map['propertyType'] ?? 'Apartment',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'ownerId': ownerId,
      'title': title,
      'description': description,
      'price': price,
      'location': location,
      'address': address,
      'bedrooms': bedrooms,
      'bathrooms': bathrooms,
      'area': area,
      'images': images,
      'amenities': amenities,
      'isAvailable': isAvailable,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'propertyType': propertyType,
    };
  }

  PropertyModel copyWith({
    String? title,
    String? description,
    double? price,
    String? location,
    String? address,
    int? bedrooms,
    int? bathrooms,
    double? area,
    List<String>? images,
    List<String>? amenities,
    bool? isAvailable,
    String? propertyType,
  }) {
    return PropertyModel(
      id: id,
      ownerId: ownerId,
      title: title ?? this.title,
      description: description ?? this.description,
      price: price ?? this.price,
      location: location ?? this.location,
      address: address ?? this.address,
      bedrooms: bedrooms ?? this.bedrooms,
      bathrooms: bathrooms ?? this.bathrooms,
      area: area ?? this.area,
      images: images ?? this.images,
      amenities: amenities ?? this.amenities,
      isAvailable: isAvailable ?? this.isAvailable,
      createdAt: createdAt,
      propertyType: propertyType ?? this.propertyType,
    );
  }
}