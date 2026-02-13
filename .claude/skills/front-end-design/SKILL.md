# Front-End Design (Spotter)

Use this skill for any Spotter UI/layout/CSS/interaction changes.

## When To Use
Use this skill when you touch any of:
- `lib/spotter_web/live/**`
- `lib/spotter_web/components/**`
- `lib/spotter_web/**.heex`
- `priv/static/assets/spotter.css`
- `assets/**`

## Non-Negotiables
- Avoid generic, boilerplate layouts.
- Keep the UI intentional and a bit surprising, but not chaotic.
- Ensure the page works on both desktop and mobile.

## Typography
- Prefer the existing font already loaded in `lib/spotter_web/components/layouts/root.html.heex`.
- Avoid default system stacks unless the existing UI already uses them.

## Color And Background
- Choose a clear visual direction.
- Prefer using/adding CSS variables instead of hard-coded colors.
- Avoid flat, single-color backgrounds unless there is a strong reason.

## Motion
- Use a small number of meaningful animations (page-load, staggered reveals).
- Avoid excessive micro-animations and noisy transitions.

## Layout And Components
- Preserve existing app shell patterns unless explicitly changing them.
- Reuse existing class conventions where possible (e.g. `.container`, `.page-header`, `.btn`, `.badge`).

## Accessibility Basics
- Every form control has a label.
- Keyboard focus is visible.
- No hover-only interactions.
- Empty and error states are clear.

## Review Checklist
- Responsive (mobile + desktop)
- Empty state
- Error state
- Loading state (where relevant)
- No regressions in navigation or spacing
