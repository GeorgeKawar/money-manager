# Feature: Notification-based transaction capture

Automatically detect income/expense transactions by reading notifications from banking/wallet/payment apps and extracting the amount via user-configurable regex rules.

## Permission & platform mechanics

- Requires Android's notification access permission (`BIND_NOTIFICATION_LISTENER_SERVICE`), granted by the user in system settings — the app cannot request this via a normal in-app permission dialog, only deep-link to the settings screen and detect current grant status.
- Implemented as a native Kotlin `NotificationListenerService` (see [../architecture.md](../architecture.md)) that:
  1. Receives every posted notification system-wide.
  2. Filters to only the app packages that have at least one enabled `NotificationRule` (avoid processing/forwarding irrelevant notifications for privacy + performance) — **except** while any enabled rule has `match_any_app = true`, which disables this filter entirely for every app; see "Any-app rules" below.
  3. Forwards `{package, title, text, timestamp}` to the Dart side over a platform/event channel.
- All regex matching and rule logic lives in Dart (shared, testable, not duplicated per platform) — the native side is a thin forwarder only.
- Notification content never leaves the device (no network call with notification text) — matching and storage are fully local.

## Rule model

See [../data-model.md](../data-model.md) `NotificationRule` table. Each rule has: target app package (or "any app" — see below), regex pattern, which capture group holds the amount, resulting transaction type (income/expense), default account, default category, enabled/disabled, **auto-add vs. review-queue** (per-rule toggle, per user decision), an explicit **priority** (evaluation order), and optional **date/note/name capture groups** — see "Matching details" below.

## Any-app rules

A rule can be configured to match notifications from **any app**, not just one `app_package` — useful when the same logical transaction can arrive from different apps, or the target app isn't known up front. When at least one enabled rule has `match_any_app = true`, the native listener skips its package-allowlist filter for every notification (it has to, since it can no longer tell in advance which package a matching rule wants) and forwards everything to Dart for rule evaluation; this trades away the allowlist's performance/privacy pre-filtering for that device while any such rule is enabled.

## Presets + custom rules

- The app ships with a small built-in set of preset rules for common patterns (generic "debited"/"credited" phrasing, a few well-known bank/wallet apps chosen later with the user). Presets are:
  - Editable and toggleable like any other rule (not locked), per user decision.
  - Marked `is_preset = true` so they can be distinguished in the UI (e.g. "Preset" badge) and potentially restored to default if the user breaks one.
- Users can add fully custom rules via a rule editor:
  1. Pick target app (from installed apps list, or type a package name manually).
  2. Enter/test a regex pattern against a sample notification text (live preview showing what the amount group would capture).
  3. Choose capture group, transaction type, default account, default category.
  4. Choose auto-add vs. send to review queue.
- A "test this rule" tool lets the user paste sample notification text and see the parsed result before saving — critical since getting a regex wrong either silently misses transactions or misparses amounts.

## Review queue (per-rule, not global)

- Per user decision, auto-add vs. review is a **per-rule setting**, not a global app setting.
- Matches from `auto_add = true` rules are inserted directly as confirmed transactions (`is_pending_review = false`).
- Matches from `auto_add = false` rules are inserted as draft transactions with `is_pending_review = true`, surfaced in a dedicated **Review queue** screen where the user can, per item:
  - Confirm as-is.
  - Edit (amount, category, account, type, date, note) then confirm.
  - Discard (delete the draft).
- Pending-review transactions are excluded from all totals/reports until confirmed (see [transactions.md](transactions.md)).
- A badge (count) indicates pending review items on the relevant nav entry.
- A transaction can also land here because it looks like a duplicate (see "Matching details" below), independent of the matched rule's own `auto_add` — shown with a distinct "possible duplicate" banner so the user doesn't confuse it with an untrusted-rule match.

## Matching details

- Regex is applied against the combined `title + "\n" + text` of the notification (exact concatenation format to finalize during implementation/testing against real sample notifications).
- Amount parsing: strip currency symbols/thousands separators per a configurable decimal/group separator assumption (default: `,` thousands, `.` decimal — revisit if the user's locale differs), parse the matched group as a number, store as integer minor units (cents).
- **Rule priority / first match wins**: the candidate rules for a notification (its package's rules, plus any `match_any_app` rules) are evaluated in ascending `priority` order — explicit and user-reorderable in the Rules screen (drag to reorder; reordering rewrites every rule's `priority` to its new position), not creation/id order. The first rule that matches wins; once one matches, no other rule is evaluated. This is what lets several rules target overlapping/same notification text with different regexes, each producing a different interpretation — priority decides which one is used, per user request.
- **Date resolution**: if a rule has a `date_group` + `date_format` and that group both captures and parses successfully, the parsed date is used as the transaction's date instead of the notification's own post time. If parsing fails (or no date group is set), the notification's post time is used — same as before this field existed.
- **Name/note resolution**: `Transaction.note` is always non-blank. Its base is the rule's `name_group` capture if the group is set and matches, else the rule's own `name` — never blank. If the rule's `note_group` is set and matches, that capture is appended to the base with " · ". (Both group settings are optional and independent — a rule can set neither, either, or both.)
- **Duplicate detection → review queue** (re-added 2026-11-18, user request, replacing the no-duplicate-protection decision of 2026-11-08): a notification/headless match that looks identical to an already-stored transaction (same `source_rule_id`, `source_app_package`, `amount_minor_units`, and resolved `date`) is **still inserted** — never silently dropped — but flagged via `Transaction.duplicate_of_transaction_id` and forced into the review queue (`is_pending_review = true`) regardless of the matched rule's own `auto_add`. The Review queue screen shows a "Looks like a duplicate of an existing transaction" banner on these items so the user decides whether to confirm (a genuine second transaction with the same shape) or discard (an actual redelivery). This replaces the 2026-11-08 "no duplicate protection" decision, which risked a real notification redelivery producing a silent, uncaught duplicate — see [data-model.md](../data-model.md) `Transaction.duplicate_of_transaction_id`. **Only applies to live/headless capture** — manual text entry (below) still has no duplicate protection at all, since there's no real notification that could have been redelivered; pasting the same text twice still produces two plain transactions.

## Manual text entry (recovering a missed notification)

Added 2026-11-13 per user request ("add a new option in the settings, to insert a text message and will check all rules and if one matches it, insert as a transaction... this way i can insert missed notifications") — a Settings row, "Insert from text" (`ManualTextEntryScreen`, `lib/features/notification_capture/presentation/manual_text_entry_screen.dart`), for the case where a real notification never reached the listener at all (background delivery limitations below, OS redaction, the user dismissed it before capture, etc.) and the user still has — or can reconstruct — its text.

- **Matching**: the user pastes/types text into one field (no separate title/text split — it's matched as-is, equivalent to a notification whose `title` is empty) and taps "Check". `NotificationCaptureService.matchManualText(text)` runs it through `matchRules()` against **every enabled rule regardless of app package** (`NotificationRulesRepository.enabledRules()`, a new package-unfiltered counterpart to `enabledRulesForPackage()`) — there's no real notification here to know a package from, so the normal per-package/any-app filtering (see "Any-app rules" above) doesn't apply; manual entry always considers every enabled rule. Same priority-ascending, first-match-wins order as live capture otherwise.
- **Preview before inserting**: matching is a pure read — nothing is written until the user reviews the result (matched rule name, resolved amount/account/category/note/date, and whether it'll post directly or go to the review queue, based on the matched rule's own `auto_add`) and taps "Insert transaction". This differs from live/headless capture, which inserts immediately on a match with no preview — deliberate here, since the user is manually keying in financial data and should get a chance to catch a wrong paste before it's recorded.
- **Date fallback**: if the matched rule has no `date_group` (or it didn't parse), the transaction uses the current date/time rather than a notification's post time (there isn't one) — shown in the preview as "right now" so the user isn't surprised, and the transaction's date is of course editable afterward like any other.
- **Insert mechanics**: shares the same insert path as live/headless capture (`NotificationCaptureService._insert()`, refactored out of `handle()` for this) — `source = 'notification'`, `source_rule_id` set to the matched rule, `source_app_package` left `null` (no real app package to record). **No duplicate protection** here, unlike live/headless capture (see "Matching details" above) — duplicate detection keys on `source_app_package`, which manual entry never sets (there's no real notification package), and there's no "redelivery" concept for text the user is deliberately typing in twice. Nothing stops the user from pasting the same text twice and getting two plain transactions.

## Known limitation: OS-level content redaction

Discovered during Phase 3 on-device testing (2026-11-02), not something this app can fix:

- Starting with Android 15, the OS (Android System Intelligence, `com.google.android.as`) classifies some posted notifications as "sensitive" and withholds their real text from third-party `NotificationListenerService` apps — the listener receives a placeholder (observed: `"Sensitive notification content hidden"`) instead of the actual notification content. This exists specifically to stop malware from scraping OTP/financial notifications via listener services.
- The bypass (`RECEIVE_SENSITIVE_NOTIFICATIONS` permission) is restricted to apps with a system signature or specific OS roles (system launcher, system UI, a couple of companion-device roles) — not obtainable by a normal app like this one.
- On the dev emulator used for testing, this redaction was applied broadly (even to notification text with no financial-looking content at all), controlled by the device_config flag `systemui/android.service.notification.redact_sensitive_notifications_from_untrusted_listeners`. Real bank transaction alerts are exactly the content type this feature targets, so expect this to affect real-world capture reliability on Android 15+ devices with Google Play Services — there is no in-app fix.
- Mitigation implemented: [`notification_capture_service.dart`](../../lib/features/notification_capture/data/notification_capture_service.dart)'s `looksRedacted()` detects the known placeholder text and, via `notificationRedactionDetectedProvider`, shows a one-time dismissible hint on the Rules screen so the user understands a missed capture isn't a broken rule. This detection is best-effort (placeholder string isn't a documented/stable API) and does not recover the real content — nothing can, from inside the app.
- Known user-side workaround (not implemented or exposed in-app): disabling Android System Intelligence's notification processing on the device. Not pursued here since it's a device setting outside the app's control, not a feature to build.

## Known limitation: background delivery on some devices

A separate limitation from the content-redaction one above — this one is about delivery/process-wake not happening at all, rather than content being withheld after successful delivery. See [background-reliability.md](background-reliability.md) (Phase 9, planned) for the full investigation: the headless capture path itself was confirmed working correctly on stock Android via a reproducible `adb` test, but OEM-specific battery/autostart restrictions on real devices can still prevent it from running. That doc covers the proposed mitigations (rebind-on-launch, battery-optimization exemption prompt, in-app diagnostics).

## Open questions
- Exact list of preset bank/app rules to ship with — needs real sample notification text from the user's own apps to write accurate regexes (can't guess bank-specific notification formats reliably). Plan: user supplies a few real (redacted of personal info) notification samples during implementation, we derive presets from those.
- Multi-line vs. truncated notification text (some apps show partial text until expanded) — may limit what's reliably parseable; address once we see real samples.
