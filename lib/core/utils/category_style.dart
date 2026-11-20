import 'package:flutter/material.dart';

/// Visual style (icon + accent color) for a category, used on the
/// transaction list's leading icon. Keyed by category name rather than a
/// stored field — simplest thing that works for the fixed default category
/// set; unrecognized (user-created) names fall back to a deterministic
/// color from [_fallbackColors] so every category still looks distinct.
class CategoryStyle {
  const CategoryStyle({required this.icon, required this.color});

  final IconData icon;
  final Color color;
}

const _defaultStyle = CategoryStyle(icon: Icons.category_outlined, color: Color(0xFF808A85));

const _byName = <String, CategoryStyle>{
  'food': CategoryStyle(icon: Icons.coffee_outlined, color: Color(0xFFBE6A4B)),
  'home': CategoryStyle(icon: Icons.home_outlined, color: Color(0xFF5B8DBE)),
  'transport': CategoryStyle(icon: Icons.directions_car_outlined, color: Color(0xFF7A6FBE)),
  'shopping': CategoryStyle(icon: Icons.shopping_bag_outlined, color: Color(0xFFBE4B8A)),
  'health': CategoryStyle(icon: Icons.favorite_outline, color: Color(0xFFBE4B4B)),
  'bills': CategoryStyle(icon: Icons.receipt_long_outlined, color: Color(0xFF4B9BAE)),
  'salary': CategoryStyle(icon: Icons.payments_outlined, color: Color(0xFF4BAE6F)),
  'freelance': CategoryStyle(icon: Icons.work_outline, color: Color(0xFF4BAE9E)),
  'gift': CategoryStyle(icon: Icons.card_giftcard_outlined, color: Color(0xFFAE8E4B)),
  'other': _defaultStyle,
};

const _fallbackColors = [
  Color(0xFFBE6A4B),
  Color(0xFF5B8DBE),
  Color(0xFF7A6FBE),
  Color(0xFFBE4B8A),
  Color(0xFFBE4B4B),
  Color(0xFF4B9BAE),
  Color(0xFF4BAE6F),
  Color(0xFFAE8E4B),
];

CategoryStyle categoryStyle(String? categoryName) {
  if (categoryName == null) return _defaultStyle;
  final known = _byName[categoryName.toLowerCase()];
  if (known != null) return known;
  final color = _fallbackColors[categoryName.hashCode.abs() % _fallbackColors.length];
  return CategoryStyle(icon: Icons.category_outlined, color: color);
}
