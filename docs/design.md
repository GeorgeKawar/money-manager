# Design reference

The user will provide additional screens over time. This doc tracks each one plus the overall visual system derived from them.

## Theming system (applies to all screens)

- **Light and dark mode are both required.** The first design received is dark-mode; a light-mode equivalent must be derived using the same tokens before/while building UI, not bolted on after.
- **Colors must be centralized and easily swappable later** — no hardcoded color values in widgets. Implementation approach: a single `AppColors`/theme-tokens source (e.g. a `ColorScheme`-driven Flutter `ThemeData` built from one small palette-definition file) that every screen reads from. Changing the palette later means editing that one file, not hunting through widgets.
- Suggested token structure (semantic, not literal hex names, so the palette can change without renaming usages): `background`, `surface`, `surfaceVariant` (e.g. the lighter card tone inside a dark surface), `primary`/`accent` (the mint-green), `onPrimary`, `positive`/`income` (green), `negative`/`expense` (red/orange), `textPrimary`, `textSecondary`, `textMuted`, `border`/`divider`.
- Both light and dark `ThemeData` are generated from the same semantic token set, just different values — this is what makes future palette changes (e.g. swapping the accent from green to blue) a one-file edit across both modes.

## Screen: Home / Dashboard

Source: user-provided mockup (dark mode), 2026-11-01.

**Layout, top to bottom:**
1. **Header** — time-of-day greeting ("GOOD EVENING", small/muted/uppercase) above a large bold title ("Your money"). A currency selector pill top-right (e.g. "SAR ⌄").
2. **All-time balance card** — large rounded card, filled with the accent color (mint green in the dark mockup), containing:
   - Small label "ALL-TIME BALANCE" + a small icon button (pulse/activity icon) top-right of the card.
   - Large balance figure (e.g. "SAR 0.00").
   - Small caption below: "Your income minus expenses".
3. **"Cash flow" section** — section title left, period navigator right (‹ November 2026 ›).
   - Segmented control with 4 options: **Day / Week / Month / Year** (matches [features/transactions.md](features/transactions.md) filtering spec exactly). Selected segment pill-highlighted.
   - Two side-by-side stat cards below the segmented control: **Income** (down-left arrow icon in a circle, green figure) and **Expenses** (up-right arrow icon in a circle, red/orange figure).
4. **"Transactions" section** — section title left, a muted subtitle line showing the active period + entry count (e.g. "November 2026 · 0 entries").
   - Empty state: centered icon (inbox/tray), bold "Nothing here yet", muted helper line "Add an income or expense to start tracking this period."
   - (Populated state not yet seen — assume a standard list per [features/transactions.md](features/transactions.md) once a mockup with data arrives.)
5. **Primary action** — originally a full-width rounded "+ Add transaction" button per the mockup; changed per user request (2026-11-06) to a small circular FAB showing only a "+" icon, pinned bottom-right.

**Visual style notes:**
- Very rounded corners throughout (cards, buttons, segmented control, pills) — large radius, consistent across components.
- Generous padding/whitespace; flat design, no heavy shadows visible.
- Dark background is a near-black with a slight green tint rather than pure black/gray.
- Accent mint-green is used for: the balance card fill, the primary button, income figures/icons, and the selected segment.
- Expense figures/icons use a warm red/orange, clearly distinct from the accent green.
- Typography: bold/heavy weight for headline numbers and titles, regular/muted smaller text for labels and captions, uppercase+letterspaced for small eyebrow labels ("GOOD EVENING", "ALL-TIME BALANCE").

**Design-driven notes for other docs:**
- Confirms the day/week/month/year filter UI as a segmented control directly on the dashboard, not a separate screen — update [features/transactions.md](features/transactions.md) dashboard description accordingly (dashboard = period-scoped summary + transaction list for that period, combined in one screen, matching the "Home/Dashboard" nav entry already assumed in [architecture.md](architecture.md)).
- "ALL-TIME BALANCE" is a new concept not yet in [data-model.md](data-model.md) — it's the all-time net across all accounts (or a specific account, depending on how the currency selector behaves — see open question below), separate from the period-scoped income/expense totals. Needs a derived-value definition added to data-model.md once confirmed.
- The top-right currency selector raises a question: is this a global display-currency switcher (requiring on-the-fly conversion across multi-currency accounts) or a filter to view one account's currency at a time? Flagged as an open question below — affects [data-model.md](data-model.md)'s "no FX conversion" assumption if it's the former.

## Screen: Add/Edit transaction

Source: user-provided mockups (dark mode, Expense + Income variants), 2026-11-01.

**Layout, top to bottom:**
1. **Header row** — title ("New transaction" / "Edit transaction" when editing) + muted subtitle "Keep your cash flow up to date.", with a circular accent-filled close ("×") button top-right.
2. **Expense/Income toggle** — a pill-shaped segmented control (not full-color-filled like the period selector): the whole control sits on `surfaceVariant`, and the *selected* segment gets a `surface`-colored highlight behind it with colored text (`expense` red/orange or `income` green); the unselected segment is plain muted text, no separate background.
3. **Amount field** — a single boxed field (`surfaceVariant` fill, large rounded corners, no visible border) showing the currency code as a small muted prefix (e.g. "SAR") beside a large bold editable number, defaulting to "0.00".
4. **Name field** — boxed text field, required (not optional), placeholder changes with the selected type ("e.g. Groceries" for expense, "e.g. Monthly salary" for income). This is the transaction's display title everywhere in the UI — distinct from its category.
5. **Category** — a `Wrap` of pill chips (not a dropdown), one row for each category of the active type. Selected chip always uses the **accent mint green** (not the expense/income color) — light accent-tinted fill + accent border + accent text; unselected chips are flat `surfaceVariant` pills with muted text. One category is always selected (first of the filtered list by default) — no "Uncategorized" option in this design.
6. **Date field** — boxed text field for manual `yyyy-MM-dd` entry (not a date-picker popup), with a small muted helper line below ("Use year-month-day, for example 2026-11-01.") that turns into an inline error message in the `expense` color if the typed date doesn't parse.
7. **Save button** — full-width accent button with a check icon + "Save transaction" / "Save changes" label.
8. **Delete** (edit mode only, not pictured in these mockups) — kept as a plain text button below Save, styled in the `expense` color.

**Notable scope decision — no account picker in this sheet:** the mockups don't show an account selector at all. Since the app only ever seeds one default "Cash" account and there's no accounts-management UI yet, the sheet auto-selects the first active account rather than showing a picker. The `Account` entity and multi-account data model are unchanged (see [data-model.md](data-model.md)) — this only hides the picker from this screen for now; revisit once an accounts UI exists.

**Design-driven notes for other docs:**
- The `Transaction.note` field is repurposed as this required "Name" — it's no longer an optional free-text note, it's the primary label shown on transaction list rows (see below). [data-model.md](data-model.md) updated accordingly.
- Default category seed list updated to match the chips shown in these mockups: **expense** = Food, Home, Transport, Shopping, Health, Bills, Other; **income** = Salary, Freelance, Gift, Other (was Food/Transport/Bills/Shopping/Entertainment/Health/Other Expense + Salary/Other Income — see [data-model.md](data-model.md) `Category`).

## Screen: Home / Dashboard — populated transaction list

Source: same mockup batch as above, 2026-11-01 (third image, "look at the transactions").

Each transaction row now shows:
- **Leading icon** — a filled circle in a per-category accent color containing a category-specific icon (e.g. a coffee cup for "Food"). Icon/color is derived from the category name via a fixed lookup (`lib/core/utils/category_style.dart`), not a user-editable field, for v1.
- **Title** — the transaction's `Name` (the required field from the add/edit sheet), falling back to the category name if somehow blank.
- **Subtitle** — `"{category} · {relative date}"`, e.g. "Food · Today" / "Food · Nov 2". Relative date collapses to "Today"/"Yesterday" for the last two days, otherwise a short date like "Nov 2" (see `relativeDateLabel` in `lib/core/utils/date_period.dart`) — replaces the previous absolute date+time subtitle.
- **Trailing** — the signed amount, plus a small trash/delete icon button that deletes the transaction directly from the list (with an "Undo" snackbar) without opening the edit sheet. Tapping elsewhere on the row still opens the edit sheet, as before.

## Resolved questions

- **Currency selector**: the "SAR ⌄" pill on the dashboard is the user's **default currency**, a single app-wide setting (not per-account display conversion, not an account filter). Per user confirmation. Changing it updates the one global default used for formatting/display app-wide; also editable from Settings, not just the dashboard shortcut. This keeps the app single-currency for v1 (no FX conversion needed) — see [data-model.md](data-model.md) `AppSettings`.
- **All-time balance** scope, as a result: sum across all accounts, since v1 is single-currency app-wide — no per-account currency mismatch to resolve.

## Open questions

- Populated (non-empty) states for the transaction list and additional screens (add/edit transaction form, categories, accounts, notification rules, settings) not yet provided — this doc will be extended as each arrives.
