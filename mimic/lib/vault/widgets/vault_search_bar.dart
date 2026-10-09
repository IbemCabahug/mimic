// lib/vault/widgets/vault_search_bar.dart
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../models/vault_tag.dart';

/// Unified Smart Vault File Locator search and tag filter bar.
class VaultSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClear;
  final String? selectedTag;
  final ValueChanged<String?> onTagSelected;
  final List<String> availableTags;
  final bool isPro;
  final VoidCallback onProRequired;
  final Widget? trailing;

  const VaultSearchBar({
    super.key,
    required this.controller,
    this.hintText = 'Search by name, caption, or #tag...',
    required this.onQueryChanged,
    required this.onClear,
    required this.selectedTag,
    required this.onTagSelected,
    this.availableTags = const [],
    this.isPro = true,
    required this.onProRequired,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    // Combine existing item tags and preset suggestions for quick tagging
    final tagsToShow = <String>{
      ...availableTags,
      ...VaultTags.presets.take(5),
    }.toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Search Text Field
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: VaultColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.grey.withValues(alpha: 0.15),
                      width: 1,
                    ),
                  ),
                  child: TextField(
                    controller: controller,
                    onChanged: onQueryChanged,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      color: VaultColors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: hintText,
                      hintStyle: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        color: VaultColors.textTertiary,
                      ),
                      prefixIcon: const Icon(
                        Icons.search,
                        size: 20,
                        color: VaultColors.textTertiary,
                      ),
                      suffixIcon: AnimatedBuilder(
                        animation: controller,
                        builder: (context, _) {
                          if (controller.text.isEmpty) return const SizedBox.shrink();
                          return IconButton(
                            icon: const Icon(Icons.clear, size: 18, color: VaultColors.textTertiary),
                            onPressed: onClear,
                          );
                        },
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
            ],
          ),
        ),

        // 2. Horizontal Tag Filter Chips
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              // 'All' filter chip
              ChoiceChip(
                label: const Text(
                  'All',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 12),
                ),
                selected: selectedTag == null,
                onSelected: (_) => onTagSelected(null),
                selectedColor: VaultColors.accent,
                backgroundColor: VaultColors.surface,
                labelStyle: TextStyle(
                  color: selectedTag == null ? Colors.white : VaultColors.textSecondary,
                  fontWeight: selectedTag == null ? FontWeight.w600 : FontWeight.normal,
                ),
                showCheckmark: false,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              const SizedBox(width: 8),

              // Tag chips
              ...tagsToShow.map((tag) {
                final isSelected = selectedTag == tag;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    avatar: !isPro
                        ? const Icon(Icons.lock_outline, size: 12, color: VaultColors.accent)
                        : null,
                    label: Text(
                      tag,
                      style: const TextStyle(fontFamily: 'Inter', fontSize: 12),
                    ),
                    selected: isSelected,
                    onSelected: (_) {
                      if (!isPro) {
                        onProRequired();
                      } else {
                        onTagSelected(isSelected ? null : tag);
                      }
                    },
                    selectedColor: VaultColors.accent,
                    backgroundColor: VaultColors.surface,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : VaultColors.textSecondary,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                    showCheckmark: false,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}
