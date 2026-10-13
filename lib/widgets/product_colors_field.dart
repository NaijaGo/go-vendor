import 'package:flutter/material.dart';

/// Seller-confirmed options; never inferred from an image or category.
class ProductColorsField extends StatelessWidget {
  const ProductColorsField({super.key, required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: TextFormField(
      controller: controller,
      decoration: const InputDecoration(
        labelText: 'Available colours (optional)',
        hintText: 'Black, Royal Blue, Cream',
        helperText:
          'List only colours available in every listed size. Choices share total stock.',
        helperMaxLines: 3,
        prefixIcon: Icon(Icons.palette_outlined),
      ),
      validator: (value) {
        final labels = (value ?? '')
            .split(',')
            .map((label) => label.trim())
            .where((label) => label.isNotEmpty)
            .toList();
        if (labels.length > 32 || labels.any((label) => label.length > 40)) {
          return 'Use up to 32 colours, with names up to 40 characters.';
        }
        return null;
      },
    ),
  );
}
