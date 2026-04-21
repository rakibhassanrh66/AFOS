import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../providers/property_provider.dart';
import '../models/property_model.dart';
import '../widgets/property_card.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  String? _selectedLocation;
  double? _minPrice;
  double? _maxPrice;
  int? _minBedrooms;
  String _selectedPropertyType = 'All';

  final List<String> _propertyTypes = [
    'All',
    'Apartment',
    'House',
    'Villa',
    'Studio',
    'Penthouse',
  ];

  final List<String> _locations = [
    'All Locations',
    'New York',
    'Los Angeles',
    'Chicago',
    'Houston',
    'Phoenix',
  ];

  List<PropertyModel> _filteredProperties = [];

  @override
  void initState() {
    super.initState();
    _filteredProperties = context.read<PropertyProvider>().properties;
  }

  void _applyFilters() {
    final properties = context.read<PropertyProvider>().properties;
    setState(() {
      _filteredProperties = properties.where((property) {
        if (_selectedLocation != null &&
            _selectedLocation != 'All Locations' &&
            property.location != _selectedLocation) {
          return false;
        }
        if (_minPrice != null && property.price < _minPrice!) {
          return false;
        }
        if (_maxPrice != null && property.price > _maxPrice!) {
          return false;
        }
        if (_minBedrooms != null && property.bedrooms < _minBedrooms!) {
          return false;
        }
        if (_selectedPropertyType != 'All' &&
            property.propertyType != _selectedPropertyType) {
          return false;
        }
        return true;
      }).toList();
    });
    Navigator.pop(context);
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.6,
              maxChildSize: 0.9,
              minChildSize: 0.4,
              expand: false,
              builder: (context, scrollController) {
                return SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Filters',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Location',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _selectedLocation ?? 'All Locations',
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        items: _locations.map((location) {
                          return DropdownMenuItem(
                            value: location,
                            child: Text(location),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setModalState(() {
                            _selectedLocation = value;
                          });
                          setState(() {});
                        },
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Property Type',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _propertyTypes.map((type) {
                          final isSelected = _selectedPropertyType == type;
                          return FilterChip(
                            label: Text(type),
                            selected: isSelected,
                            onSelected: (selected) {
                              setModalState(() {
                                _selectedPropertyType = type;
                              });
                              setState(() {});
                            },
                            selectedColor: AppColors.primary.withValues(alpha: 0.2),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Price Range',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Min',
                                prefixText: '\$ ',
                              ),
                              onChanged: (value) {
                                _minPrice = double.tryParse(value);
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Max',
                                prefixText: '\$ ',
                              ),
                              onChanged: (value) {
                                _maxPrice = double.tryParse(value);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Bedrooms',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: [1, 2, 3, 4, 5].map((count) {
                          final isSelected = _minBedrooms == count;
                          return FilterChip(
                            label: Text('$count+'),
                            selected: isSelected,
                            onSelected: (selected) {
                              setModalState(() {
                                _minBedrooms = selected ? count : null;
                              });
                              setState(() {});
                            },
                            selectedColor: AppColors.primary.withValues(alpha: 0.2),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 32),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                setModalState(() {
                                  _selectedLocation = null;
                                  _minPrice = null;
                                  _maxPrice = null;
                                  _minBedrooms = null;
                                  _selectedPropertyType = 'All';
                                });
                                setState(() {});
                              },
                              child: const Text('Clear'),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _applyFilters,
                              child: const Text('Apply'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Search properties...',
                            prefixIcon: const Icon(Icons.search),
                            filled: true,
                            fillColor: AppColors.grey100,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: IconButton(
                          onPressed: _showFilterSheet,
                          icon: const Icon(
                            Icons.tune,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: Consumer<PropertyProvider>(
                builder: (context, provider, _) {
                  final properties = _searchController.text.isEmpty
                      ? _filteredProperties
                      : provider.properties
                          .where((p) => p.title
                              .toLowerCase()
                              .contains(_searchController.text.toLowerCase()))
                          .toList();

                  if (properties.isEmpty) {
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search_off,
                            size: 64,
                            color: AppColors.grey400,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'No properties found',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: properties.length,
                    itemBuilder: (context, index) {
                      final property = properties[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: PropertyCard(
                          property: property,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}