# Shamell Superapp – Accessibility Checklist (Flutter)

This document is a practical checklist for accessibility in the Shamell
Superapp (Flutter). The goal is to keep the app usable for:

- Screen‑reader users
- Users with visual or motor impairments
- Users with large text / increased system font size

Most items apply to `clients/shamell_flutter`.

---

## 1. Core Principles

- **Contrast & readability**
  - Use dark text on light background or high‑contrast colours in dark mode.
  - Do not rely on colour alone to convey important information.
  - Use `Theme.of(context).textTheme.*` for text sizes instead of hard‑coded
    font sizes.

- **Keyboard and focus handling**
  - Wrap complex containers (sheets, dialogs) in `FocusTraversalGroup` so the
    focus order is predictable.
  - Interactive elements should clearly respond to focus/hover.

- **Screen‑reader support**
  - Add `Semantics` (or meaningful `label` values) to important buttons and
    custom controls.
  - Expose status changes (errors, success, warnings) via readable
    `StatusBanner` / snack bars, not only visually.

---

## 2. Existing Patterns

### 2.1 Taxi Rider / Mobility

File: `clients/shamell_flutter/lib/core/taxi/taxi_rider.dart`

- Key actions with semantics:
  - **Pay & request ride**
    - `Semantics(button: true, label: "Pay and request taxi ride")`
    - AR label: `الدفع وطلب الرحلة`
  - **Status**
    - `Semantics(label: "Show ride status")`
    - AR label: `عرض حالة الرحلة`
  - **Cancel**
    - `Semantics(label: "Cancel ride")`
    - AR label: `إلغاء الرحلة`

File: `clients/shamell_flutter/lib/core/mobility_history.dart`

- Filter:
  - Clear title (`l.filterLabel`, EN/AR) and dropdown with
    `statusAll/completed/canceled`.
- Content:
  - List of `StandardListTile` for Taxi/Bus with date, status and
    driver/trip information.

### 2.2 Payments

File: `clients/shamell_flutter/lib/core/payments_send.dart`

- Buttons:
  - **Send**
    - `Semantics(button: true, label: "Send payment")`
    - AR: `إرسال دفعة`
  - **Contacts**
    - `Semantics(button: true, label: "Open contacts")`
    - AR: `فتح قائمة جهات الاتصال`

File: `clients/shamell_flutter/lib/core/home_routes.dart`

- Quick‑action chips (`_QuickChip`):
  - `Semantics(button: true, label: l.qaScanPay / l.qaP2P / …)`.
- Home satellites (`_Sat`):
  - `Semantics(button: true, selected: ...)` with EN/AR labels
    (`homeTaxi`, `homePayments`, …).

### 2.3 Status / Errors

File: `clients/shamell_flutter/lib/core/status_banner.dart`

- `StatusBanner.info/success/warning/error` is used in key flows:
  - Payments send
  - Taxi rider (quote / booking / status)
  - Bus/Stays/Food (order/booking status)

This keeps error messages visually and semantically consistent.

---

## 3. Checklist for New or Updated Screens

When building a new screen or flow, consciously check:

1. **Labels & L10n**
   - Are all user‑visible strings wired through `L10n` (EN/AR)?
   - Do buttons and menu items have descriptive text
     (`"Send payment"` rather than just `"Send"` out of context)?

2. **Semantics for custom controls**
   - If you build your own button/slider/tile:
     - Use `Semantics(button: true, label: ...)` or `Semantics(
       toggled: ..., selected: ...)` as appropriate.
   - Are sliders / slide‑buttons (e.g. Taxi slide) understandable for
     screen‑reader users?

3. **Focus order**
   - Do you have multiple interactive zones (e.g. draggable sheet + list)?
     - Use `FocusTraversalGroup` and, if needed, `OrderedTraversalPolicy`,
       similar to `_SheetContainer` in `home_routes.dart`.

4. **Errors and hints**
   - Are errors only printed or shown as a raw `out` string?
     - Prefer `StatusBanner` + snackbars with clear error messages.
   - Are there understandable empty states
     (e.g. `"No payments yet"` / `لا توجد مدفوعات بعد`)?

5. **Contrast and tap targets**
   - Are tap targets large enough (roughly ≥ 44x44 dp)?
   - Does text have sufficient contrast (especially in dark mode)?

---

## 4. Recommended A11y Review Process

1. **Developer self‑check**
   - Run through this checklist when building a new screen.
   - Set semantics labels consciously, especially on primary actions.

2. **Screen‑reader smoke test**
   - Enable a screen reader on device/emulator:
     - Android: TalkBack
     - iOS: VoiceOver
   - Walk through the core flows:
     - Login, home, first payment, taxi ride, journey/mobility.
   - Listen for confusing or missing announcements.

3. **Targeted widget tests**
   - For critical elements (login labels, primary buttons), add small
     widget tests that assert semantics labels:
     - Example: `payments_widgets_test.dart` asserts that the wrapped
       `SendButton` has `SemanticsFlag.isButton` and label `"Send payment"`.

4. **Periodic review**
   - For larger UI refactors, do a short a11y review once per release
     (screen‑reader smoke test + quick look at semantics structure).

---

## 5. Next Steps

If you want to harden accessibility further, consider:

- Additional semantics labels for:
  - Food order actions.
  - History filters (e.g. wallet history, requests).
- Systematic testing at large text sizes:
  - Run the app with increased system font size and ensure layouts do
    not break (text wraps instead of being cut off; important buttons
    stay visible).

This document should evolve: when new modules or major UI refactors are
added, extend the checklist and notes for how they fit into the overall
accessibility strategy.

