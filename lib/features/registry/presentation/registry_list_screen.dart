import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Generic registry provider
final registryDataProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, tableName) async {
  return await Supabase.instance.client.from(tableName).select('*');
});

class RegistryListScreen extends ConsumerWidget {
  final String tableName;
  final String title;
  final List<String> displayFields;

  const RegistryListScreen({
    super.key,
    required this.tableName,
    required this.title,
    this.displayFields = const ['name'],
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(registryDataProvider(tableName));

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: asyncData.when(
        data: (data) => ListView.builder(
          itemCount: data.length,
          itemBuilder: (context, i) {
            final item = data[i];
            return ListTile(
              title: Text(item[displayFields[0]] ?? 'No Name'),
              subtitle: displayFields.length > 1 ? Text(item[displayFields[1]] ?? '') : null,
            );
          },
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Add navigation logic to Create screen
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
