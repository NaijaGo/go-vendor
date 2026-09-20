import 'package:flutter/material.dart';

/// Explicit attributes complement category inference; blank means infer rather
/// than silently assigning the listing to a gender or age group.
class ProductSearchAttributesField extends StatelessWidget {
  const ProductSearchAttributesField({
    super.key,
    required this.initialValues,
    required this.onChanged,
  });
  final Map<String, String> initialValues;
  final void Function(String field, String value) onChanged;

  @override
  Widget build(BuildContext context) {
    Widget text(String field, String label, String hint, int maxLength) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextFormField(
            initialValue: initialValues[field] ?? '',
            maxLength: maxLength,
            decoration: InputDecoration(labelText: label, hintText: hint),
            onChanged: (value) => onChanged(field, value.trim()),
          ),
        );
    Widget select(
      String field,
      String label,
      Map<String, String> options,
    ) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: options.containsKey(initialValues[field])
            ? initialValues[field]
            : '',
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: options.entries
            .map(
              (entry) =>
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            )
            .toList(),
        onChanged: (value) => onChanged(field, value ?? ''),
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Help shoppers find your product',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
            const SizedBox(height: 8),
            const Text(
              'Choose accurate attributes. Leave audience blank if it does not apply; never add unrelated search tags.',
            ),
            const SizedBox(height: 16),
            text('brand', 'Brand', 'The actual product brand', 120),
            select('gender', 'Audience', const {
              '': 'Infer from category / tags',
              'female': 'Women / female',
              'male': 'Men / male',
              'unisex': 'Unisex',
              'unspecified': 'Not specified',
            }),
            select('ageGroup', 'Age group', const {
              '': 'Infer from category / tags',
              'adult': 'Adults',
              'child': 'Children',
              'all': 'All ages',
            }),
            text(
              'productType',
              'Product type',
              'dress, shirt, shoes, phone...',
              60,
            ),
            text(
              'searchTags',
              'Search tags',
              'cotton, casual, blue (comma separated)',
              600,
            ),
          ],
        ),
      ),
    );
  }
}
