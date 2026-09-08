import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/data/firebase/mappers.dart';
import 'package:little_blue_market/models/models.dart';

void main() {
  const listing = DirectoryListing(
    id: '47494',
    ownerUid: 'u1',
    title: 'Field Trips Travel & Vacations',
    status: 'publish',
    link: 'https://littlebluecart.com/directory-vendors/listing/field-trips/',
    website: 'www.example.test/advisor',
    email: 'Owner@Example.test',
    phone: '(561) 414-0509',
    state: 'FL',
    address: '1851 Massachusetts Ave NE, St. Petersburg, FL 33703',
    categories: ['Travel'],
    tags: ['Woman-Owned'],
    locations: ['Online/Virtual'],
    plan: 'DIRECTORY SHOWCASE PLAN',
  );

  test('a listing knows how to be reached', () {
    expect(listing.isPublished, isTrue);
    expect(listing.statusLabel, 'Published');
    expect(listing.planLabel, 'Showcase plan');
    expect(listing.stateLabel, 'FL');
    expect(listing.websiteUri.toString(), 'https://www.example.test/advisor');
    expect(listing.callUri.toString(), 'tel:5614140509');
    expect(listing.emailUri.toString(), 'mailto:Owner@Example.test');
    expect(listing.directionsUri.toString(), startsWith('geo:0,0?q=1851'));
    expect(listing.linkUri, isNotNull);
  });

  test('a pending listing without an address falls back to the directory location', () {
    const pending = DirectoryListing(
      id: '2',
      ownerUid: 'u1',
      title: 'Pop-Up',
      status: 'pending',
      link: '',
      locationLabel: '*Online/Virtual Business',
      plan: 'FREE',
    );
    expect(pending.statusLabel, 'Under review');
    expect(pending.stateLabel, 'Online/Virtual Business');
    expect(pending.planLabel, 'Free');
    expect(pending.callUri, isNull);
    expect(pending.directionsUri, isNull);
    expect(pending.linkUri, isNull);
  });

  test('the mirror document maps back, names already resolved', () {
    final mapped = FirestoreMappers.directoryListing('47494', {
      'ownerUid': 'u1',
      'title': 'Field Trips',
      'status': 'pending',
      'link': 'https://x.test/l/',
      'categories': ['Travel', 'Art/Creative'],
      'tags': ['Woman-Owned'],
      'locations': ['Minnesota'],
      'state': 'MN',
      'plan': 'DIRECTORY SHOWCASE PLAN',
    });
    expect(mapped.id, '47494');
    expect(mapped.categories, ['Travel', 'Art/Creative']);
    expect(mapped.stateLabel, 'MN');
    expect(mapped.statusLabel, 'Under review');
    expect(mapped.imageUrl, '');
  });

  test('a website order reads as a person would say it', () {
    final order = DirectoryOrder(
      id: '88',
      number: '1088',
      status: 'on-hold',
      createdAt: DateTime(2026, 9, 1),
      totalCents: 4500,
      currency: 'USD',
      items: const [
        DirectoryOrderItem(name: 'Hoodie', quantity: 1, totalCents: 4000),
        DirectoryOrderItem(name: 'Sticker', quantity: 2, totalCents: 500),
      ],
      viewUrl: 'https://x.test/my-account/view-order/88/',
    );
    expect(order.statusLabel, 'On hold');
    expect(order.dateLabel, 'Sep 1, 2026');
    expect(order.summary, 'Hoodie · Sticker ×2');
    expect(order.totalLabel, Fmt.money(4500));
  });
}
