import 'package:flutter/material.dart';

import '../database/database.dart';

/// Visual style (icon + accent color) for a category, used on the
/// transaction list's leading icon.
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

/// Icon choices offered by the add/edit category sheet's icon picker, keyed
/// by the stable string stored in `Category.icon` — the key, not the
/// [IconData] itself, is what's persisted, so these keys must never change
/// once shipped (renaming a key would silently revert existing categories to
/// their name-based fallback icon).
const categoryIconChoices = <String, IconData>{
  'category': Icons.category_outlined,
  'coffee': Icons.coffee_outlined,
  'restaurant': Icons.restaurant_outlined,
  'home': Icons.home_outlined,
  'car': Icons.directions_car_outlined,
  'bus': Icons.directions_bus_outlined,
  'flight': Icons.flight_outlined,
  'bag': Icons.shopping_bag_outlined,
  'cart': Icons.shopping_cart_outlined,
  'heart': Icons.favorite_outline,
  'fitness': Icons.fitness_center_outlined,
  'receipt': Icons.receipt_long_outlined,
  'bolt': Icons.bolt_outlined,
  'wifi': Icons.wifi_outlined,
  'phone': Icons.phone_iphone_outlined,
  'payments': Icons.payments_outlined,
  'savings': Icons.savings_outlined,
  'work': Icons.work_outline,
  'school': Icons.school_outlined,
  'gift': Icons.card_giftcard_outlined,
  'pets': Icons.pets_outlined,
  'movie': Icons.movie_outlined,
  'sports': Icons.sports_soccer_outlined,
  'medical': Icons.local_hospital_outlined,
};

/// Color choices offered by the add/edit category sheet's color picker,
/// stored as `Category.color` (ARGB `Color.value`).
const categoryColorChoices = <Color>[
  Color(0xFFBE6A4B),
  Color(0xFF5B8DBE),
  Color(0xFF7A6FBE),
  Color(0xFFBE4B8A),
  Color(0xFFBE4B4B),
  Color(0xFF4B9BAE),
  Color(0xFF4BAE6F),
  Color(0xFFAE8E4B),
  Color(0xFF4BAE9E),
  Color(0xFF808A85),
  Color(0xFFBE9B4B),
  Color(0xFF6FA84B),
];

/// Resolves the icon+color to show for [category]: its own stored
/// `icon`/`color` when set (2026-11-20, user request — see
/// docs/features/categories-accounts.md), otherwise the fixed name-based
/// lookup (for the seeded default categories) or a deterministic
/// name-hashed color (for any other unstyled category), same as before
/// these columns were wired up.
CategoryStyle categoryStyle(Category? category) {
  if (category == null) return _defaultStyle;
  final fallback = _byName[category.name.toLowerCase()] ??
      CategoryStyle(
        icon: Icons.category_outlined,
        color: _fallbackColors[category.name.hashCode.abs() % _fallbackColors.length],
      );
  return CategoryStyle(
    icon: categoryIconChoices[category.icon] ?? fallback.icon,
    color: category.color != null ? Color(category.color!) : fallback.color,
  );
}
