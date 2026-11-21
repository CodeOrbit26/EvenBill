import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/inputs/app_text_field.dart';
import '../../core/widgets/feedback/app_snackbar.dart';
import '../../core/di/injection.dart';
import '../../core/models/group_model.dart';

/// Shows the reusable "Create New Group" / "Start a new group" bottom sheet.
Future<GroupModel?> showCreateGroupModal({
  required BuildContext context,
  String? defaultCurrency,
  Function(GroupModel newGroup)? onGroupCreated,
}) async {
  final nameController = TextEditingController();
  String selectedType = 'TRIP';
  String selectedCurrency = defaultCurrency ?? 'INR';
  bool simplifyDebts = true;
  bool isSubmitting = false;

  return showModalBottomSheet<GroupModel>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: AppRadius.roundedTopSheet),
    builder: (ctx) => StatefulBuilder(
      builder: (modalContext, setModalState) {
        final isDark = Theme.of(modalContext).brightness == Brightness.dark;

        final currencyOptions = [
          {'code': 'INR', 'flag': '🇮🇳', 'label': 'INR (₹)'},
          {'code': 'USD', 'flag': '🇺🇸', 'label': 'USD (\$)'},
          {'code': 'EUR', 'flag': '🇪🇺', 'label': 'EUR (€)'},
          {'code': 'GBP', 'flag': '🇬🇧', 'label': 'GBP (£)'},
          {'code': 'JPY', 'flag': '🇯🇵', 'label': 'JPY (¥)'},
          {'code': 'CAD', 'flag': '🇨🇦', 'label': 'CAD (C\$)'},
        ];

        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(modalContext).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: (isDark ? AppColors.mintAccent : AppColors.forestGreen).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.group_add_rounded,
                            color: isDark ? AppColors.mintAccent : AppColors.forestGreen,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Create New Group',
                          style: AppTypography.titleLarge(isDark).copyWith(fontSize: 20),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Organize shared expenses for a trip, housemates, couple, or event.',
                  style: AppTypography.bodyMedium(isDark).copyWith(fontSize: 13),
                ),
                const SizedBox(height: AppSpacing.md),

                AppTextField(
                  label: 'Group Name',
                  hintText: 'e.g. Kyoto Trip, Apt 404, Summer Vacation',
                  controller: nameController,
                  prefixIcon: Icons.group_outlined,
                ),
                const SizedBox(height: AppSpacing.md),

                Text('Group Purpose', style: AppTypography.labelLarge(isDark).copyWith(fontSize: 13)),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: 8,
                  children: ['TRIP', 'HOME', 'COUPLE', 'OTHER'].map((type) {
                    final isSelected = selectedType == type;
                    return ChoiceChip(
                      label: Text(type),
                      selected: isSelected,
                      selectedColor: isDark
                          ? AppColors.mintAccent.withOpacity(0.25)
                          : AppColors.forestGreen.withOpacity(0.15),
                      labelStyle: TextStyle(
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected
                            ? (isDark ? AppColors.mintAccent : AppColors.forestGreen)
                            : null,
                      ),
                      onSelected: (val) {
                        if (val) setModalState(() => selectedType = type);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: AppSpacing.md),

                Text('Base Currency', style: AppTypography.labelLarge(isDark).copyWith(fontSize: 13)),
                const SizedBox(height: AppSpacing.xs),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: currencyOptions.map((c) {
                      final isSelected = selectedCurrency == c['code'];
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ChoiceChip(
                          label: Text('${c['flag']} ${c['code']}'),
                          selected: isSelected,
                          selectedColor: isDark
                              ? AppColors.mintAccent.withOpacity(0.25)
                              : AppColors.forestGreen.withOpacity(0.15),
                          labelStyle: TextStyle(
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: isSelected
                                ? (isDark ? AppColors.mintAccent : AppColors.forestGreen)
                                : null,
                          ),
                          onSelected: (val) {
                            if (val) setModalState(() => selectedCurrency = c['code']!);
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Simplify Group Debts', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  subtitle: const Text(
                    'Automatically nets circular balances into the minimum number of cash transfers.',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: simplifyDebts,
                  activeColor: isDark ? AppColors.mintAccent : AppColors.forestGreen,
                  onChanged: (val) => setModalState(() => simplifyDebts = val),
                ),
                const SizedBox(height: AppSpacing.lg),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDark ? AppColors.mintAccent : AppColors.forestGreen,
                      foregroundColor: isDark ? AppColors.darkBackground : Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    onPressed: isSubmitting
                        ? null
                        : () async {
                            final name = nameController.text.trim();
                            if (name.isEmpty) {
                              AppSnackbar.showError(ctx, 'Please enter a group name');
                              return;
                            }

                            setModalState(() => isSubmitting = true);
                            try {
                              final newGroup = await Injection.groupRepository.createGroup(
                                name: name,
                                groupType: selectedType,
                                baseCurrency: selectedCurrency,
                                simplifyDebts: simplifyDebts,
                              );
                              if (ctx.mounted) Navigator.pop(ctx, newGroup);
                              if (context.mounted) {
                                AppSnackbar.showSuccess(context, 'Group "${newGroup.name}" created successfully!');
                                onGroupCreated?.call(newGroup);
                              }
                            } catch (e) {
                              setModalState(() => isSubmitting = false);
                              if (ctx.mounted) {
                                AppSnackbar.showError(ctx, 'Failed to create group: $e');
                              }
                            }
                          },
                    child: isSubmitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Create Group', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
