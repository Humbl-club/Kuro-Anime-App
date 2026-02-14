# Concierge UI Acceptance Checklist

**Last updated:** 2026-02-14

Target mode: **concierge_editorial_v1 ON, light-only** (no dark-mode rendering branch in this acceptance path).

## Layout
- [x] Editorial column layout: all content flows in a single `LazyVStack` with `KuroDesignSpacing` tokens
- [x] No floating elements collide with reading flow (mascot constrained, not overlapping input/content)
- [x] Horizontal padding uses `KuroDesignSpacing.padding` (20pt) where canonical; legacy 16/18pt variants remain only in compact component contexts.
- [x] Vertical spacing between messages uses `KuroDesignSpacing.md` (16pt)
- [x] Empty state (ConciergeIntroCard + ConciergeStarterActions) flows as clean editorial column
- [x] Input field pinned to bottom, separated by divider

## Typography
- [x] All active concierge body/caption/title text uses KuroDesignSystem tokens: `.kuroBody()`, `.kuroCaption()`, `.kuroTitle()`, `.kuroMicro()`
- [x] Serif fonts (`.design(.serif)`) used for headings; default design for body/caption/micro
- [ ] No raw `.system(size:)` calls outside KuroDesignSystem.swift (small number of component-level serif/default uses still to migrate)
- [x] Tracking values align with current editorial token usage

## Motion
- [ ] All animations use `KuroAnimation` tokens (`.editorial`, `.fast`, `.standard`) — there is still one decorative spring in concierge shell to justify.
- [ ] Springs use `KuroAnimation.editorial` (response: 0.6, dampingFraction: 0.82) as primary motion budget.
- [ ] No `.linear()` animations in core message/interaction paths (there is currently one non-core decorative orbit animation path to review).
- [x] No UIKit animation wrappers (UIView.animate)
- [ ] Message insertion uses `.move(edge: .bottom).combined(with: .opacity)` transition

## Haptics
- [x] Haptics fire on explicit user actions: send, confirm, toggle, paste, select
- [x] No haptics on scroll, typing, or passive state changes
- [x] Uses `KuroAccessibility.impactHaptic(.light)` for selections
- [x] Uses `KuroAccessibility.impactHaptic(.medium)` for confirm/apply

## Accessibility
- [x] ConciergeIntroCard has `.accessibilityElement(children: .combine)` with label
- [ ] VoiceOver labels on all interactive elements (buttons, toggles, cards) [in-progress]
- [ ] Recommendation cards have `.accessibilityLabel` and `.accessibilityHint` [in-progress]
- [ ] Dynamic Type respected (no fixed heights that clip large text) [in-progress]
- [x] Keyboard dismiss on scroll via `.scrollDismissesKeyboard(.interactively)`

## Performance Budget
| Metric | Target | Measurement |
|--------|--------|-------------|
| Typing latency (view recompute) | < 16ms | `#if DEBUG` CFAbsoluteTime on input change |
| First paint (view appear to content visible) | < 300ms | CFAbsoluteTime onAppear to first render |
| Scroll FPS | 60fps steady | Instruments Time Profiler |
| Send-to-optimistic-message | < 5ms | CFAbsoluteTime in send() |
| Parse response to bubble render | < 50ms | CFAbsoluteTime in handleImportFlow |
| Image prefetch start | < 10ms after response | CFAbsoluteTime in prefetch block |

## Monochrome Palette
- [x] No colored status indicators (no green/blue/orange dots in core flow)
- [x] Status text uses `black.opacity(0.55)` as primary neutral status tone
- [x] Pill backgrounds use `black.opacity(0.06)` and muted borders
- [x] Red preserved for destructive actions (leave/delete, where appropriate)
- [x] User bubbles: solid black fill (light mode); dark-mode behavior is out of scope for this light-only acceptance pass.
- [x] Assistant bubbles: `Color.kuroSecondaryBackground.opacity(0.96)` fill
