import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/database/database.dart';
import 'package:money_manager/features/notification_capture/data/notification_capture_service.dart';
import 'package:money_manager/features/notification_capture/data/notification_rules_repository.dart';
import 'package:money_manager/platform/notification_listener/notification_listener_channel.dart';

// Exercises NotificationCaptureService.handle() against a real (in-memory)
// database — the layer both entry paths described in docs/architecture.md
// ("Notification capture — how the app gets invoked") funnel through. This
// covers what an on-device adb test cannot right now: Android 15's
// sensitive-notification redaction (see docs/features/notification-capture.md
// "Known limitation") strips the text of every synthetic notification this
// emulator can post, so the insert/dedupe logic below is verified here
// instead of via a live device round trip.
void main() {
  late AppDatabase db;
  late NotificationRulesRepository rulesRepository;
  late NotificationCaptureService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    rulesRepository = NotificationRulesRepository(db);
    service = NotificationCaptureService(db, rulesRepository);
  });

  tearDown(() => db.close());

  CapturedNotification notification({
    String package = 'com.bank.app',
    String text = 'Your account was debited 10.50',
    DateTime? postTime,
  }) {
    return CapturedNotification(package: package, title: '', text: text, postTime: postTime ?? DateTime(2026, 11, 2, 9, 0));
  }

  test('inserts a review-queue transaction for a non-auto-add rule', () async {
    final ruleId = await rulesRepository.addRule(
      name: 'Test bank',
      appPackage: 'com.bank.app',
      regexPattern: r'debited ([\d.]+)',
      amountGroup: 1,
      transactionType: 'expense',
      defaultAccountId: 1,
      autoAdd: false,
    );

    final redacted = await service.handle(notification());
    expect(redacted, isFalse);

    final rows = await db.select(db.transactions).get();
    expect(rows, hasLength(1));
    expect(rows.single.amountMinorUnits, 10500);
    expect(rows.single.isPendingReview, isTrue);
    expect(rows.single.sourceRuleId, ruleId);
    expect(rows.single.source, 'notification');
  });

  test('inserts a confirmed transaction directly for an auto-add rule', () async {
    await rulesRepository.addRule(
      name: 'Test bank',
      appPackage: 'com.bank.app',
      regexPattern: r'debited ([\d.]+)',
      amountGroup: 1,
      transactionType: 'expense',
      defaultAccountId: 1,
      autoAdd: true,
    );

    await service.handle(notification());

    final rows = await db.select(db.transactions).get();
    expect(rows, hasLength(1));
    expect(rows.single.isPendingReview, isFalse);
  });

  test('a redelivered notification still inserts, but flagged as a duplicate and forced into review '
      '(re-added 2026-11-18, replacing the 2026-11-08 removal)', () async {
    await rulesRepository.addRule(
      name: 'Test bank',
      appPackage: 'com.bank.app',
      regexPattern: r'debited ([\d.]+)',
      amountGroup: 1,
      transactionType: 'expense',
      defaultAccountId: 1,
      autoAdd: true,
    );

    final n = notification();
    await service.handle(n);
    await service.handle(n);

    final rows = await db.select(db.transactions).get()
      ..sort((a, b) => a.id.compareTo(b.id));
    expect(rows, hasLength(2));
    expect(rows[0].isPendingReview, isFalse);
    expect(rows[0].duplicateOfTransactionId, isNull);
    expect(rows[1].isPendingReview, isTrue, reason: 'forced into review despite the rule being auto-add');
    expect(rows[1].duplicateOfTransactionId, rows[0].id);
  });

  test('manual text entry is never flagged as a duplicate, even for an identical match', () async {
    final ruleId = await rulesRepository.addRule(
      name: 'Test bank',
      appPackage: 'com.bank.app',
      regexPattern: r'debited ([\d.]+)',
      amountGroup: 1,
      transactionType: 'expense',
      defaultAccountId: 1,
      autoAdd: true,
    );

    final match1 = await service.matchManualText('Your account was debited 10.50');
    await service.insertManualMatch(match1!);
    final match2 = await service.matchManualText('Your account was debited 10.50');
    await service.insertManualMatch(match2!);

    final rows = await db.select(db.transactions).get();
    expect(rows, hasLength(2));
    expect(rows.every((r) => r.duplicateOfTransactionId == null), isTrue);
    expect(rows.every((r) => !r.isPendingReview), isTrue);
    expect(rows.every((r) => r.sourceRuleId == ruleId), isTrue);
  });

  test('a later notification with the same rule but a different amount still inserts', () async {
    await rulesRepository.addRule(
      name: 'Test bank',
      appPackage: 'com.bank.app',
      regexPattern: r'debited ([\d.]+)',
      amountGroup: 1,
      transactionType: 'expense',
      defaultAccountId: 1,
      autoAdd: false,
    );

    await service.handle(notification(text: 'Your account was debited 10.50'));
    await service.handle(notification(text: 'Your account was debited 20.00', postTime: DateTime(2026, 11, 2, 9, 5)));

    final rows = await db.select(db.transactions).get();
    expect(rows, hasLength(2));
    expect(rows.every((r) => r.duplicateOfTransactionId == null), isTrue);
  });

  test('an any-app rule inserts separate transactions for same-amount notifications from different apps', () async {
    await rulesRepository.addRule(
      name: 'Any bank',
      appPackage: '',
      matchAnyApp: true,
      regexPattern: r'debited ([\d.]+)',
      amountGroup: 1,
      transactionType: 'expense',
      defaultAccountId: 1,
      autoAdd: false,
    );

    await service.handle(notification(package: 'com.bank.one', postTime: DateTime(2026, 11, 2, 9, 0)));
    await service.handle(notification(package: 'com.bank.two', postTime: DateTime(2026, 11, 2, 9, 0)));

    final rows = await db.select(db.transactions).get();
    expect(rows, hasLength(2));
    expect(rows.map((r) => r.sourceAppPackage), containsAll(['com.bank.one', 'com.bank.two']));
  });

  test('does nothing for a package with no enabled rules', () async {
    final redacted = await service.handle(notification(package: 'com.unrelated.app'));
    expect(redacted, isFalse);
    expect(await db.select(db.transactions).get(), isEmpty);
  });

  test('reports redaction and does not insert when the OS has hidden the text', () async {
    await rulesRepository.addRule(
      name: 'Test bank',
      appPackage: 'com.bank.app',
      regexPattern: r'debited ([\d.]+)',
      amountGroup: 1,
      transactionType: 'expense',
      defaultAccountId: 1,
      autoAdd: false,
    );

    final redacted = await service.handle(notification(text: 'Sensitive notification content hidden'));
    expect(redacted, isTrue);
    expect(await db.select(db.transactions).get(), isEmpty);
  });
}
