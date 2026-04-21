import 'package:flutter/foundation.dart';
import '../models/property_model.dart';

class PropertyProvider extends ChangeNotifier {
  List<PropertyModel> _properties = [];
  List<PropertyModel> _myProperties = [];
  bool _isLoading = false;

  List<PropertyModel> get properties => _properties;
  List<PropertyModel> get myProperties => _myProperties;
  bool get isLoading => _isLoading;

  PropertyProvider() {
    _loadDummyProperties();
  }

  void _loadDummyProperties() {
    _properties = [
      PropertyModel(
        id: '1',
        ownerId: 'owner1',
        title: 'Modern Apartment',
        description: 'A beautiful modern apartment in the heart of the city',
        price: 2500,
        location: 'Downtown',
        address: '123 Main St',
        bedrooms: 2,
        bathrooms: 2,
        area: 1200,
        images: [],
        amenities: ['WiFi', 'Pool', 'Gym'],
        createdAt: DateTime.now(),
        propertyType: 'Apartment',
      ),
      PropertyModel(
        id: '2',
        ownerId: 'owner1',
        title: 'Cozy Villa',
        description: 'A spacious villa with garden and pool',
        price: 4500,
        location: 'Suburbs',
        address: '456 Oak Ave',
        bedrooms: 4,
        bathrooms: 3,
        area: 2500,
        images: [],
        amenities: ['WiFi', 'Pool', 'Parking'],
        createdAt: DateTime.now(),
        propertyType: 'Villa',
      ),
      PropertyModel(
        id: '3',
        ownerId: 'owner2',
        title: 'Studio Loft',
        description: 'Perfect for students or young professionals',
        price: 1200,
        location: 'University District',
        address: '789 College Rd',
        bedrooms: 1,
        bathrooms: 1,
        area: 600,
        images: [],
        amenities: ['WiFi', 'Laundry'],
        createdAt: DateTime.now(),
        propertyType: 'Studio',
      ),
      PropertyModel(
        id: '4',
        ownerId: 'owner2',
        title: 'Luxury Penthouse',
        description: 'Stunning penthouse with panoramic city views',
        price: 8000,
        location: 'High Rise District',
        address: '101 Sky Tower',
        bedrooms: 3,
        bathrooms: 3,
        area: 3000,
        images: [],
        amenities: ['WiFi', 'Pool', 'Gym', 'Concierge'],
        createdAt: DateTime.now(),
        propertyType: 'Penthouse',
      ),
    ];
    _myProperties = _properties.where((p) => p.ownerId == 'owner1').toList();
  }

  void addProperty(PropertyModel property) {
    _properties.add(property);
    if (property.ownerId == 'owner1') {
      _myProperties.add(property);
    }
    notifyListeners();
  }

  List<PropertyModel> getPropertiesByOwner(String ownerId) {
    return _properties.where((p) => p.ownerId == ownerId).toList();
  }
}
