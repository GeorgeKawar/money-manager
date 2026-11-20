# Feature: Recurring transactions

For predictable repeating income/expenses: salary, rent, subscriptions, loan payments, etc.

See [../data-model.md](../data-model.md) `RecurringTransaction` table for schema.

## Creating a recurring definition

- Same fields as a normal transaction (account, category, type, amount, note) plus: frequency (daily/weekly/monthly/yearly), start date, optional end date.
- Shown in a dedicated "Recurring" list (under Settings or its own section — finalize placement with designs) separate from the main transaction list, showing: name/note, amount, frequency, next run date, active/paused toggle.

## Generation behavior

- On app launch, check all `is_active = true` recurring definitions where `next_run_date <= today`; for each, generate a `Transaction` row (`source = recurring`, `recurring_id` set) and advance `next_run_date` by the frequency interval. Repeat until `next_run_date > today` (handles catch-up if the app wasn't opened for a while — generates all missed occurrences, doesn't skip them).
- No reliance on exact background-time execution for v1 (no `AlarmManager`/`WorkManager` exact scheduling) — generation happens lazily on app open. If the user wants transactions to appear even without opening the app (e.g. for timely budget alerts), that's a later enhancement using `WorkManager` periodic work.
- Pausing (`is_active = false`) stops future generation without deleting past generated transactions.
- Editing a recurring definition only affects future-generated transactions, not ones already created.

## Open questions
- Custom intervals (e.g. "every 2 weeks", "every 3 months") — not in v1 scope unless requested; the four fixed frequencies cover the common cases (salary=monthly, rent=monthly, some subscriptions=yearly, etc.).
- Whether to notify the user when a recurring transaction is about to post or just posted — deferred, depends on whether local notifications are wanted as a feature at all (separate from notification *capture*, this would be the app *sending* a notification).
