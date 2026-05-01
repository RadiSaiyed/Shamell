# Flutter Blueprint: Feature-First

## Folder strategy
Use feature-first organization:
- `v2/features/<feature>/domain`
- `v2/features/<feature>/application`
- `v2/features/<feature>/infrastructure`
- `v2/features/<feature>/presentation`

## UI architecture
- Shared design tokens/components under `v2/design`.
- Widgets stay presentational where possible.
- State lives in feature controllers/view-models.
- Use one state-management style per feature module (no mixed patterns inside one feature).

## UX intent
- Fast first success in <= 30s for core actions.
- Consistent empty/loading/error handling.
- Meaningful motion and visual hierarchy via design system.
