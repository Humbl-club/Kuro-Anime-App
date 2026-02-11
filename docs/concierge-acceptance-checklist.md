# Concierge UI Acceptance Checklist

## Layout
- [ ] Editorial column layout: all content flows in a single `LazyVStack` with `KuroDesignSpacing` tokens
- [ ] No floating elements collide with reading flow (mascot constrained, not overlapping input/content)
- [ ] Horizontal padding uses `KuroDesignSpacing.padding` (20pt) consistently
- [ ] Vertical spacing between messages uses `KuroDesignSpacing.md` (16pt)
- [ ] Empty state (ConciergeIntroCard + ConciergeStarterActions) flows as clean editorial column
- [ ] Input field pinned to bottom, separated by 0.5pt divider

## Typography
- [ ] All fonts use KuroDesignSystem tokens: `.kuroBody()`, `.kuroCaption()`, `.kuroTitle()`, `.kuroMicro()`
- [ ] Serif fonts (`.design(.serif)`) used only for titles/headlines
- [ ] Default design (`.design(.default)`) used for body/caption/micro
- [ ] No raw `.system(size:)` calls outside KuroDesignSystem.swift
- [ ] Tracking values match editorial guidelines (captions: 1.6-2.4, micro: 1.8)

## Motion
- [ ] All animations use `KuroAnimation` tokens (`.editorial`, `.fast`, `.standard`)
- [ ] Springs use `KuroAnimation.editorial` (response: 0.6, dampingFraction: 0.82)
- [ ] No `.linear()` animations
- [ ] No UIKit animation wrappers (UIView.animate)
- [ ] Message insertion uses `.move(edge: .bottom).combined(with: .opacity)` transition

## Haptics
- [ ] Haptics fire only on explicit user actions: send, confirm, toggle, paste, select
- [ ] No haptics on scroll, typing, or passive state changes
- [ ] Uses `KuroAccessibility.impactHaptic(.light)` for selections
- [ ] Uses `KuroAccessibility.impactHaptic(.medium)` for confirm/apply

## Accessibility
- [ ] VoiceOver labels on all interactive elements (buttons, toggles, cards)
- [ ] ConciergeIntroCard has `.accessibilityElement(children: .combine)` with label
- [ ] Recommendation cards have `.accessibilityLabel` and `.accessibilityHint`
- [ ] Dynamic Type respected (no fixed heights that clip large text)
- [ ] Keyboard dismiss on scroll via `.scrollDismissesKeyboard(.interactively)`

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
- [ ] No colored status indicators (no green/blue/orange dots)
- [ ] Status text uses `black.opacity(0.55)`
- [ ] Pill backgrounds use `black.opacity(0.06)`
- [ ] Red only for destructive actions (leave/delete)
- [ ] User bubbles: solid black fill (light mode), white.opacity(0.10) (dark mode)
- [ ] Assistant bubbles: `Color.kuroSecondaryBackground.opacity(0.96)` fill
