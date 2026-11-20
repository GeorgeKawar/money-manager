import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/category_style.dart';
import '../../../core/widgets/sheet_widgets.dart';
import '../data/categories_repository.dart';
import 'add_edit_category_sheet.dart';

final _categoriesFilterProvider = StateProvider.autoDispose<String>((ref) => 'expense');

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final categoriesAsync = ref.watch(activeCategoriesProvider);
    final filter = ref.watch(_categoriesFilterProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SheetTypeToggle(
                    type: filter,
                    onChanged: (t) => ref.read(_categoriesFilterProvider.notifier).state = t,
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: categoriesAsync.when(
                      data: (categories) {
                        final filtered = categories.where((c) => c.type == filter).toList();
                        if (filtered.isEmpty) {
                          return Center(
                            child: Text('No categories yet.', style: TextStyle(color: colors.textSecondary)),
                          );
                        }
                        return ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final category = filtered[index];
                            final style = categoryStyle(category.name);
                            return InkWell(
                              onTap: () => showAddEditCategorySheet(context, existing: category),
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                decoration: BoxDecoration(
                                  color: colors.surface,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: colors.border),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(color: style.color.withValues(alpha: 0.18), shape: BoxShape.circle),
                                      child: Icon(style.icon, color: style.color, size: 18),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        category.name,
                                        style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 16),
                                      ),
                                    ),
                                    Icon(Icons.chevron_right, color: colors.textMuted),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Center(child: Text('Could not load categories: $e')),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 16,
              child: ElevatedButton.icon(
                onPressed: () => showAddEditCategorySheet(context, initialType: filter),
                icon: const Icon(Icons.add),
                label: const Text('Add category'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
