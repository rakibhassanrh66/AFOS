import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';

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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: Text(title, style: AppTextStyles.headlineMed.copyWith(color: AppColors.textPrimaryOf(context)))),
      body: asyncData.when(
        data: (data) => ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: data.length,
          itemBuilder: (context, i) {
            final item = data[i];
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                  color: AppColors.surfaceOf(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
              child: ListTile(
                title: Text(item[displayFields[0]] ?? 'No Name',
                    style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimaryOf(context))),
                subtitle: displayFields.length > 1
                    ? Text(item[displayFields[1]] ?? '',
                        style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context)))
                    : null,
              ),
            );
          },
        ),
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.blue)),
        error: (err, stack) => Center(
            child: Text('Error: $err', style: TextStyle(color: AppColors.textSecondaryOf(context)))),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.blue,
        onPressed: () {
          // Add navigation logic to Create screen
        },
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
