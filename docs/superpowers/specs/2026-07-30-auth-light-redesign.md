# Kuro Auth — Light Redesign

**Date:** 2026-07-30  
**Status:** Approved for implementation  
**Refs:** Mobbin — Wabi, Genie, Cosmos, Comet (light frame)

## Goal
Replace the plain caption-style `AuthView` with a light, tactile welcome + email flow: stronger logo, recognizable pills, press motion.

## Screens

### Welcome
- Light Kuro background
- Dimensional Kuro mark (idle float)
- 4–5 glowing cover orbs (trending anime covers when available)
- Pill CTAs: Continue with Apple (system button, pill clip), Continue with Email (black)
- Legal line
- Press scale ~0.97 + light haptic

### Email (sign-in / create)
- Back to welcome
- Wordmark + title (“Welcome back” / “Create account”)
- Soft inset email + password fields (existing validation)
- Black Continue / Create pill
- Mode switch + Forgot password (sign-in)
- Same auth backends as today

## Out of scope
Dark mode, Google SSO, onboarding redesign, Letterboxd-style full-bleed stills

## Success
Auth feels branded and pressable on Simulator; existing email/Apple auth still works.
