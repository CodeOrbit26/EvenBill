import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/buttons/primary_button.dart';
import '../../core/widgets/feedback/app_snackbar.dart';
import '../../core/di/injection.dart';
import '../../core/models/split_template_model.dart';

class SplitPresetPickerModal extends StatefulWidget {
  final String groupId;
  final List<Map<String, String>> members;
  final ValueChanged<SplitTemplateModel> onTemplateSelected;

  const SplitPresetPickerModal({
    super.key,
    required this.groupId,
    required this.members,
    required this.onTemplateSelected,
  });

  @override
  State<SplitPresetPickerModal> createState() => _SplitPresetPickerModalState();
}

class _SplitPresetPickerModalState extends State<SplitPresetPickerModal> {
  bool _isLoading = true;
  List<SplitTemplateModel> _templates = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final list = await Injection.proRepository.getSplitTemplates(widget.groupId);
      if (mounted) {
        setState(() {
          _templates = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _createNewPreset() async {
    final nameController = TextEditingController(text: 'Couples (60/40 Split)');
    final isConfirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save New Group Split Preset'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Preset Name', style: AppTypography.labelSmall()),
            const SizedBox(height: AppSpacing.xs),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(hintText: 'e.g. 60/40 Split or Equal 3-way'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Create Preset')),
        ],
      ),
    );

    if (isConfirmed == true && nameController.text.trim().isNotEmpty) {
      try {
        final allocations = widget.members.map((m) {
          final isFirst = m == widget.members.first;
          return {
            'user_id': m['id']!,
            'value': isFirst ? 60.0 : 40.0,
          };
        }).toList();

        final created = await Injection.proRepository.createSplitTemplate(
          groupId: widget.groupId,
          name: nameController.text.trim(),
          splitType: 'PERCENTAGE',
          allocations: allocations,
          isDefault: _templates.isEmpty,
        );

        if (mounted) {
          AppSnackbar.showSuccess(context, 'Split preset "${created.name}" created!');
          _loadTemplates();
        }
      } catch (e) {
        if (mounted) {
          AppSnackbar.showError(context, 'Failed to save preset: $e');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.65,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.tune_rounded, color: AppColors.primaryForest),
                  const SizedBox(width: AppSpacing.sm),
                  Text('Saved Split Presets', style: AppTypography.titleMedium().copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Apply saved group split ratios in one tap or create default presets.',
            style: AppTypography.bodySmall(),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, style: AppTypography.bodySmall()))
                    : _templates.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.bookmarks_outlined, size: 48, color: AppColors.secondaryEvergreen.withOpacity(0.5)),
                                const SizedBox(height: AppSpacing.sm),
                                Text('No split presets saved yet', style: AppTypography.titleSmall()),
                                const SizedBox(height: AppSpacing.xs),
                                Text('Create recurring split ratios for this group', style: AppTypography.bodySmall()),
                              ],
                            ),
                          )
                        : ListView.separated(
                            itemCount: _templates.length,
                            separatorBuilder: (context, _) => const SizedBox(height: AppSpacing.xs),
                            itemBuilder: (context, index) {
                              final tmpl = _templates[index];
                              return Card(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: tmpl.isDefault
                                        ? AppColors.mintAccent.withOpacity(0.3)
                                        : Theme.of(context).dividerColor.withOpacity(0.1),
                                    child: Icon(
                                      tmpl.isDefault ? Icons.star_rounded : Icons.splitscreen_rounded,
                                      color: tmpl.isDefault ? AppColors.primaryForest : Colors.grey,
                                      size: 20,
                                    ),
                                  ),
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text(tmpl.name, style: AppTypography.bodyMedium().copyWith(fontWeight: FontWeight.bold)),
                                      ),
                                      if (tmpl.isDefault)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppColors.primaryForest,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            'DEFAULT',
                                            style: AppTypography.labelSmall().copyWith(color: Colors.white, fontSize: 10),
                                          ),
                                        ),
                                    ],
                                  ),
                                  subtitle: Text(
                                    'Split Method: ${tmpl.splitType} • ${tmpl.allocations.length} members',
                                    style: AppTypography.bodySmall(),
                                  ),
                                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                                  onTap: () {
                                    widget.onTemplateSelected(tmpl);
                                    Navigator.of(context).pop();
                                  },
                                ),
                              );
                            },
                          ),
          ),
          const SizedBox(height: AppSpacing.sm),
          PrimaryButton(
            label: '+ Create New Split Preset',
            onPressed: _createNewPreset,
          ),
        ],
      ),
    );
  }
}
