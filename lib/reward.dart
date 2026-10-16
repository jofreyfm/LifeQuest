class Reward {
  final int? id;
  final String title;
  final String description;
  final String category;
  final int price;
  final int? maxRedemptions;
  final int redeemedCount;

  const Reward({this.id, required this.title, this.description = '',
    this.category = 'Lazer', required this.price, this.maxRedemptions,
    this.redeemedCount = 0});

  bool get available => maxRedemptions == null || redeemedCount < maxRedemptions!;

  Map<String, Object?> toMap() => {
    'title': title, 'description': description, 'category': category,
    'price': price, 'max_redemptions': maxRedemptions,
  };

  factory Reward.fromMap(Map<String, Object?> map) => Reward(
    id: map['id'] as int, title: map['title'] as String,
    description: map['description'] as String,
    category: map['category'] as String,
    price: map['price'] as int,
    maxRedemptions: map['max_redemptions'] as int?,
    redeemedCount: (map['redeemed_count'] as int?) ?? 0,
  );
}

class OwnedReward {
  final int id;
  final String title;
  final String description;
  final int price;
  final DateTime purchasedAt;
  final DateTime? usedAt;

  const OwnedReward({required this.id, required this.title,
    required this.description, required this.price,
    required this.purchasedAt, this.usedAt});

  bool get used => usedAt != null;

  factory OwnedReward.fromMap(Map<String, Object?> map) => OwnedReward(
    id: map['id'] as int,
    title: map['title_snapshot'] as String,
    description: map['description_snapshot'] as String,
    price: map['price_paid'] as int,
    purchasedAt: DateTime.parse(map['purchased_at'] as String),
    usedAt: map['used_at'] == null ? null : DateTime.parse(map['used_at'] as String),
  );
}
