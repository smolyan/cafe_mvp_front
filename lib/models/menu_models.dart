// Модели под твой реальный JSON с бэка

// ===== Бизнес-ланч (business-lunch.json) =====

class BusinessLunch {
  final int price;
  final String currency;
  final List<String> items;

  BusinessLunch({
    required this.price,
    required this.currency,
    required this.items,
  });

  factory BusinessLunch.fromJson(Map<String, dynamic> json) {
    return BusinessLunch(
      price: json['price'] as int,
      currency: json['currency'] as String,
      items: (json['items'] as List<dynamic>).map((e) => e as String).toList(),
    );
  }
}

// ===== Корневой объект меню (menu.json) =====

class MenuResponse {
  final String date;
  final String source;
  final List<MenuCategory> categories;

  MenuResponse({
    required this.date,
    required this.source,
    required this.categories,
  });

  factory MenuResponse.fromJson(Map<String, dynamic> json) {
    final rawCategories = json['категории'] as Map<String, dynamic>;

    final categories = rawCategories.entries.map((entry) {
      final categoryName = entry.key; // например "Салаты"
      final data = entry.value as Map<String, dynamic>;
      return MenuCategory.fromJson(categoryName, data);
    }).toList();

    return MenuResponse(
      date: json['дата'] as String,
      source: json['источник'] as String? ?? '',
      categories: categories,
    );
  }
}

// ===== Категория =====

class MenuCategory {
  final String name; // "Салаты", "Супы" и т.п.
  final String categoryId;
  final List<MenuDish> dishes;

  MenuCategory({
    required this.name,
    required this.categoryId,
    required this.dishes,
  });

  factory MenuCategory.fromJson(String name, Map<String, dynamic> json) {
    final dishes = (json['блюда'] as List<dynamic>)
        .map((e) => MenuDish.fromJson(e as Map<String, dynamic>))
        .toList();

    return MenuCategory(
      name: name,
      categoryId: json['category_id'] as String,
      dishes: dishes,
    );
  }
}

// ===== Блюдо =====

class MenuDish {
  final String id;
  final String title;
  final String description;
  final int price;
  final String currency;

  MenuDish({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    required this.currency,
  });

  factory MenuDish.fromJson(Map<String, dynamic> json) {
    return MenuDish(
      id: json['dish_id'] as String,
      title: json['название'] as String,
      description: json['описание'] as String? ?? '',
      price: json['цена'] as int,
      currency: json['currency'] as String,
    );
  }
}
