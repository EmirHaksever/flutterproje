import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterproje/constants/categories.dart';
import 'package:flutterproje/models/friend.dart';
import 'package:flutterproje/models/list_item.dart';
import 'package:flutterproje/models/shopping_list.dart';
import 'package:flutterproje/widgets/ui_kit.dart';

void main() {
  group('categoryEmoji', () {
    test('"Market" içindeki "et" 🥩 vermez (regresyon)', () {
      expect(categoryEmoji('Market'), '🛒');
    });
    test('"Kıyafet" → 👕, "et" yakalanmaz', () {
      expect(categoryEmoji('Kıyafet'), '👕');
    });
    test('bilinen kategoriler', () {
      expect(categoryEmoji('Meyve'), '🍎');
      expect(categoryEmoji('Süt Ürünleri'), '🥛');
      expect(categoryEmoji('Et & Balık'), '🥩');
      expect(categoryEmoji('Temizlik'), '🧴');
    });
    test('bilinmeyen → 🛒', () {
      expect(categoryEmoji('Zurna Malzemeleri'), '🛒');
    });
  });

  group('ShoppingList.fromMap', () {
    test('gömülü list_items ürün sayısını verir', () {
      final l = ShoppingList.fromMap({
        'id': 'a',
        'user_id': 'u',
        'name': 'Haftalık',
        'created_at': '2026-01-01T00:00:00Z',
        'completion_rate': 0.5,
        'list_items': [
          {'id': '1'},
          {'id': '2'},
          {'id': '3'},
        ],
      });
      expect(l.name, 'Haftalık');
      expect(l.itemCount, 3);
      expect(l.completionRate, 0.5);
      expect(l.isOwner, true);
    });

    test('eksik alanlarda çökmez', () {
      final l = ShoppingList.fromMap({'id': 'a'});
      expect(l.name, 'İsimsiz Liste');
      expect(l.itemCount, 0);
    });
  });

  group('ListItem.fromMap', () {
    test('image_url + temel alanlar', () {
      final i = ListItem.fromMap({
        'id': 'x',
        'list_id': 'l',
        'product_name': 'Süt',
        'category': 'Süt Ürünleri',
        'quantity': 2,
        'is_completed': true,
        'created_at': '2026-01-01T00:00:00Z',
        'image_url': 'https://x/y.jpg',
        'tags': ['organik', 'büyük'],
      });
      expect(i.productName, 'Süt');
      expect(i.quantity, 2);
      expect(i.isCompleted, true);
      expect(i.imageUrl, 'https://x/y.jpg');
      expect(i.tags, ['organik', 'büyük']);
    });

    test('toInsert image_url içerir', () {
      final i = ListItem(
        id: '',
        listId: 'l',
        productName: 'Ekmek',
        imageUrl: 'u',
        createdAt: DateTime(2026),
      );
      expect(i.toInsert()['image_url'], 'u');
      expect(i.toInsert()['product_name'], 'Ekmek');
    });
  });

  group('Friend.fromMap (friend_id join)', () {
    test('join geldiğinde isim + avatar okunur, displayName isme düşer', () {
      final f = Friend.fromMap({
        'id': 'r',
        'user_id': 'me',
        'friend_id': 'other',
        'status': 'accepted',
        'added_at': '2026-01-01T00:00:00Z',
        'friend': {
          'email': 'a@b.com',
          'name': 'Ayşe',
          'avatar_url': 'https://x/a.png',
        },
      });
      expect(f.friendId, 'other');
      expect(f.friendEmail, 'a@b.com');
      expect(f.friendName, 'Ayşe');
      expect(f.avatarUrl, 'https://x/a.png');
      expect(f.displayName, 'Ayşe');
    });

    test('isim yoksa displayName e-postaya düşer', () {
      final f = Friend.fromMap({
        'id': 'r',
        'user_id': 'me',
        'friend_id': 'other',
        'status': 'accepted',
        'added_at': '2026-01-01T00:00:00Z',
        'friend': {'email': 'a@b.com'},
      });
      expect(f.displayName, 'a@b.com');
    });
  });

  group('mergeDiscoveredCategories', () {
    test('varsayılanlar + keşfedilenler birleşir, tekrar yok', () {
      final merged = mergeDiscoveredCategories({'Meyve', 'Özel Kategori'});
      final names = merged.map((c) => c['name'] as String).toList();
      expect(names.contains('Özel Kategori'), true);
      expect(names.where((n) => n == 'Meyve').length, 1);
    });
  });

  testWidgets('PercentRing %-metnini gösterir', (tester) async {
    await tester.pumpWidget(const _Host(child: PercentRing(value: 0.65)));
    expect(find.text('%65'), findsOneWidget);
  });

  testWidgets('MiniStatCard değer + etiket', (tester) async {
    await tester.pumpWidget(
      const _Host(child: MiniStatCard(value: '8', label: 'Bekleyen')),
    );
    expect(find.text('8'), findsOneWidget);
    expect(find.text('Bekleyen'), findsOneWidget);
  });

  testWidgets('ProductSuggestions sorguya göre filtreler + seçilince döner',
      (tester) async {
    ({String name, String? category})? picked;
    await tester.pumpWidget(_Host(
      child: ProductSuggestions(
        query: 'sü',
        pool: const [
          (name: 'Süt', category: 'Süt Ürünleri'),
          (name: 'Ekmek', category: null),
        ],
        exclude: const {},
        onPick: (m) => picked = m,
      ),
    ));
    expect(find.text('Süt'), findsOneWidget);
    expect(find.text('Ekmek'), findsNothing);
    await tester.tap(find.text('Süt'));
    expect(picked?.name, 'Süt');
  });

  testWidgets('EmptyState başlık + mesaj + buton', (tester) async {
    var tapped = false;
    await tester.pumpWidget(_Host(
      child: EmptyState(
        icon: Icons.inbox,
        title: 'Bildirim yok',
        message: 'Sonra tekrar bak.',
        actionLabel: 'Yenile',
        onAction: () => tapped = true,
      ),
    ));
    expect(find.text('Bildirim yok'), findsOneWidget);
    expect(find.text('Sonra tekrar bak.'), findsOneWidget);
    await tester.tap(find.text('Yenile'));
    expect(tapped, true);
  });
}

class _Host extends StatelessWidget {
  const _Host({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(body: Center(child: child)),
      );
}
