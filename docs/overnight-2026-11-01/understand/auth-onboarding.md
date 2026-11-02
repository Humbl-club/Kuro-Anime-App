# Auth + onboarding audit (overnight 2026-11-01, read-only lane)

Lane: auth-onboarding. Personas: Senior iOS Engineer + Senior Security Engineer (auth, GDPR/DSGVO).
Scope: app launch → `RootView` gate → `AuthView` (welcome / email / Sign in with Apple / forgot password) → `kuro://auth/callback` → `OnboardingView` → first page in `ContentView`; account deletion reachability; `emails/`; `supabase/functions/auth-callback`; `check_email_exists`.
Method: source reads only. Nothing was modified, built or deployed, and no remote service was touched. SDK behaviour was read from the local SwiftPM cache of `supabase-swift` at tag `v2.54.1`, the version CLAUDE.md pins (`~/Library/Caches/org.swift.swiftpm/repositories/supabase-swift-a07f8e78`, `git show v2.54.1:<path>`).
Uncertainty markers: **[VERIFIED]** means read in source. **[INFERRED]** means it follows from source but was not run. **[DASHBOARD?]** means it depends on Supabase Dashboard settings, which are not in the repo (there is no `supabase/config.toml`).

---

## 0. Executive summary

1. **Password reset is most likely broken end to end (HIGH, [INFERRED], conditional on the dashboard).**
   - Mechanism: the SDK defaults to PKCE, but the app's callback parser only accepts implicit `access_token` links, so the reset link the email carries is silently ignored.
   - Even if a token link did arrive, the app has no "choose a new password" step. A reset just signs the user in.
2. **The login-CSRF issue is confirmed (HIGH, [VERIFIED]).** While signed out, the app adopts any supplied `kuro://auth/callback` token pair. The fix in §5 uses PKCE as the device binding, plus a local pending-flow record that carries flow type and expiry. It is client-only and also fixes item 1.
3. **Sign-in blocks passwords shorter than 8 characters (HIGH if legacy accounts exist, [VERIFIED] in the client).** The app's own error mapping still says the server minimum is 6, so older accounts with 6–7 character passwords may be locked out of email sign-in.
4. **Email enumeration (MEDIUM, GDPR-relevant).** `check_email_exists` is SECURITY DEFINER and executable by anon, with no rate limit. The sign-up UI turns it into a live "Taken" oracle.
5. **The AuthView form is off-brand and not accessible (MEDIUM).**
   - Brand: blue focus colours and red accent on non-destructive elements.
   - Accessibility: fixed `.system(size:)` fonts with no Dynamic Type, no `@FocusState` or Return-key chain, unlabeled icon buttons, and errors that are never announced.
   - Localization: no German, although Onboarding and the rejected-callback banner have it.
   - Adaptivity: iPhone landscape is allowed but the layout is built on height percentages.
6. **Onboarding is outdated (MEDIUM).** It describes a pager that no longer exists (Browse instead of Home), uses generic SF-Symbol cards instead of the approved welcome language, its completion flag is per device rather than per account, and it doesn't respect Reduce Motion.
7. **Legal surfaces are missing (MEDIUM, DSGVO).**
   - Terms and Privacy are plain text on the welcome screen, not links, and there is no Terms URL anywhere.
   - All 5 email templates and the edge page load Google Fonts from Google's servers.
   - There is no telemetry or consent disclosure at sign-up.
8. **The welcome scenery matches the approved b943e457 version ([VERIFIED]).** `KuroSceneryLoop(.login)` reproduces the old `AuthSceneryLoop` exactly: same tile, 34 s period, saturation 1.02 and the same white gradient. It adds a Reduce Motion / Low Power / scene-phase still frame. Keep it.

---

## 1. Files read (authority list)

| Area | File |
|---|---|
| App entry, root gate, URL handling | `Kuro/KuroApp.swift` (191 lines) |
| Deep-link parsing | `Kuro/Services/DeepLinkRouter.swift` (101) |
| Session funnel | `Kuro/Identity/SessionController.swift` (832) |
| Auth transport | `Kuro/Identity/AuthService.swift` (285) |
| Callback guard | `Kuro/Identity/AuthCallbackGuard.swift` (55) |
| UI identity | `Kuro/Identity/IdentityStore.swift` (38) |
| Auth UI | `Kuro/Views/AuthView.swift` (1388) |
| Welcome scenery | `Kuro/Views/KuroSceneryLoop.swift` (99) |
| Onboarding | `Kuro/Views/OnboardingView.swift` (252); presented from `Kuro/ContentView.swift:164, 530–537` |
| Account section | `Kuro/Views/ProfileView.swift:531–611, 650–705, 1087–1112` |
| Client construction | `Kuro/Composition/AppComposition.swift:128–144` |
| Info.plist | project root (`plutil -p Info.plist`) |
| Backend | `supabase/functions/auth-callback/index.ts` (315), `supabase/functions/delete-account/{handler,adapters}.ts`, `supabase/migrations/20260225100000_check_email_exists_rpc.sql` |
| Emails | `emails/{confirm,reset-password,magic-link,change-email,invite}.html` |
| Tests | `KuroTests/AccountLifecycleTests.swift:513–610`, `KuroTests/IdentityCompositionTests.swift:662–682, 925–940` |
| SDK (v2.54.1) | `Sources/Auth/Defaults.swift:32`, `Sources/Supabase/Types.swift:89`, `Sources/Auth/AuthClient.swift:731–760, 941–1052, 1467–1496, 1560–1583`, `Sources/Auth/AuthError.swift` |
| Prior notes | `CURRENT_APP_STATE.md:920–936, 19610`, `docs/plans/2026-10-08-native-design-polish.md`, `docs/handoffs/2026-10-08-fresh-session/HANDOFF.md:89` |

---

## 2. State diagram (text)

```
                         ┌──────────────────────────────────────────────┐
 app launch ─────────────►  KuroApp.init  (URLCache 64/256 MB)           │ KuroApp.swift:40-51
                         │  AppComposition.shared → makeClient()         │ AppComposition.swift:128-144
                         └───────────────┬──────────────────────────────┘
                                         │
              client == nil ─────────────┼───────────── client != nil
                    │                                         │ startLaunchRestore(): isAuthBootstrapping = true
                    ▼                                         ▼ SessionController.swift:118-122
        [CONFIG ERROR screen]                     [BOOTSTRAP screen] "KURO" + ProgressView
        KuroApp.swift:138-154                     KuroApp.swift:155-166 (systemBackground; not branded)
        (terminal; onOpenURL ignored :84)                 │ restoreSession() :243-306
                                                          │
                     ┌────────────────────────────────────┼─────────────────────────────────────┐
                     │ stored session valid               │ transport error + stored session    │ no/revoked session
                     ▼                                    ▼ (offline presentation restore :290-297)▼
                applySession → isAuthenticated=true   applySession (no server check)        endSessionAfterFailedRestore :299
                     │                                    │                                      │
                     └──────────────┬─────────────────────┘                                      ▼
                                    ▼                                                    [AUTH: WELCOME]
                            [CONTENT] ContentView.id(userId)  KuroApp.swift:167-172      AuthView.welcomeStep :143-227
                                    │                                                    KuroSceneryLoop banner (52% h)
                                    │ showOnboarding = !UserDefaults("kuro_onboarding_completed")  "Get started" → EMAIL(signIn)
                                    ▼ ContentView.swift:164, 530-537                       Apple button → Apple sheet
                            [ONBOARDING] fullScreenCover, 5 cards                                │
                              Skip / Continue / last CTA                                         │
                              → .home  : selection unchanged (.discover, or .home when           │
                                         seriesHome flag on: ContentView.swift:338-341)          │
                              → .tasteDeck: selection = .taste  :533-535                         │
                                    ▼                                                            │
                            [FIRST PAGE] Home (seriesHome) | Discover | Taste                    │
                                                                                                 │
   [AUTH: EMAIL]  AuthView.emailStep :283-436   ◄────────────────────────────────────────────────┘
     mode tabs: signIn ("Welcome back"/"Let’s get started") | signUp ("Join Kuro"/"Create your shelf")
     email field ─ revalidateEmail :536-556
         empty → .empty ; regex fail → .invalidFormat("Invalid")
         signIn → .available immediately
         signUp → .checking → 500 ms debounce → check_email_exists RPC → .taken("Taken") | .available(✓)
                  (RPC error/offline → false → .available)  AuthService.swift:158-175
     password field ─ revalidatePassword :558-561 → .tooShort("Min 8") | .valid(✓)   (BOTH modes)
     submit tap :385-399
         !canSubmit → inline error (one of 4 strings :389-395)
         canSubmit  → submit() :599-614 → isWorking spinner
              signIn  → SessionController.signInWithEmail :431-442 → authenticate(endsSessionOnFailure: true)
              signUp  → SessionController.signUpWithEmail :444-457 → authenticate(endsSessionOnFailure: false)
                          session nil (email confirmation ON) → endSession(), return WITHOUT error :211-215  ← silent
              success → applySession → isAuthenticated → RootView swaps to CONTENT (AuthView torn down)
              failure → identity.authErrorMessage = userFacingAuthErrorMessage → errorText (red)
     "Forgot password?" (signIn only) :416-427 → forgotPassword() :646-661
              no "@" → "Enter your email above, then tap Forgot password."
              AuthService.resetPassword → SDK resetPasswordForEmail(redirectTo: kuro://auth/callback)
                  SDK (PKCE default) stores code_verifier in Keychain + sends code_challenge  AuthClient.swift:1472, 1560-1573
              ok → errorText = "Password reset email sent. Check your inbox." (rendered in error red)
     back chevron → WELCOME

   [APPLE] SignInWithAppleButton :457-472 → nonce (SecRandom) → handleAppleSignIn :616-644
              success → SessionController.signInWithApple → afterPublish saveFullName
              ANY error incl. user cancel → generic "Something went wrong." + forced jump to EMAIL step :638-643

   [EMAIL LINK] user taps email button → Supabase /verify → 303 to redirect_to
        PKCE (current SDK default) → kuro://auth/callback?code=…           ← DeepLink.from returns nil (needs access_token) → DROPPED
        implicit (only if PKCE not used) → kuro://auth/callback#access_token=…&refresh_token=…&type=recovery
              → KuroApp.onOpenURL :83-99 → SessionController.handleAuthCallback :478-532
                    signed in : AuthCallbackGuard sub+exp check (fail closed) → setSession → same-user re-check
                    signed out: guard returns .proceed unconditionally (AuthCallbackGuard.swift:32)  ← LOGIN CSRF
                    → setSession → applySession → bootstrap   (type discarded; no new-password step)
              failure → authErrorMessage "Verification failed. Please request a new link."
                        (lost if AuthView is on WELCOME: :108-113 copies to errorText, which only EMAIL renders)

   [SIGN OUT]  ProfileView "Sign Out" :538-545 → SessionController.signOut :595-619 → AUTH: WELCOME
   [DELETE]    ProfileView "Delete Account" :549-583 → alert → (Apple? obtainAppleAuthorizationCode) →
               SessionController.deleteAccount :546-593 → delete-account fn → local sign-out → AUTH: WELCOME
```

### Transition table (UI states)

| State | Entry | Exits | Loading UI | Error UI | Offline |
|---|---|---|---|---|---|
| Config error | `identity.configError != nil` (`KuroApp.swift:138`) | none | n/a | `error` string verbatim | n/a |
| Bootstrap | `isAuthBootstrapping` (`:155`) | Content or Auth | `ProgressView` | none | Offline restore is allowed with a stored session (`SessionController.swift:290–297`, `AuthService.swift:214–225`) |
| Welcome | default `step = .welcome` (`AuthView.swift:19–29`) | Email (Get started), Apple sheet | none | **not rendered** (errorText exists but the welcome step never shows it) | No indicator beyond the global "OFFLINE" strip (`KuroApp.swift:127–135`). The Apple button stays enabled. |
| Email form | `goToEmail` (`:116–124`) | Welcome (chevron), Content (success) | spinner inside the CTA (`:402`), `isWorking` disables buttons, not fields | red 13 pt text (`:378–383`) | Submit runs and the transport error maps to "No internet connection…" (`AuthService.swift:232–233`) |
| Apple sheet | system | Content or Email (on any error) | `isWorking` | generic message | Server leg fails with the transport message |
| Callback apply | `onOpenURL` | Content, or stays on Auth | **none** (no visible progress while `setSession` runs) | `authErrorMessage` (welcome step: lost; content: banner when rejected only) | Fails with "Verification failed." |
| Onboarding | first Content after install | Content | none | none | Static, works offline |

### 2.1 Every user-facing message in the journey

| String (as shipped) | Site | Trigger | Proposed EN / DE |
|---|---|---|---|
| "Enter your email to continue." | `AuthView.swift:389` | submit with empty email | keep / "Gib deine E-Mail-Adresse ein." |
| "Password needs at least 8 characters." | `AuthView.swift:391` | submit with short password (**also on sign-in**, S4) | sign-up only: "Use at least 8 characters." / "Mindestens 8 Zeichen." |
| "That email is already in use." | `AuthView.swift:393` | sign-up, RPC said taken | remove with S5; replaced by the server `userAlreadyExists` mapping |
| "Check your email and password." | `AuthView.swift:395` | invalid format, or still checking | "Enter a valid email address." / "Gib eine gültige E-Mail-Adresse ein." |
| "Invalid" / "Taken" / "Min 8" (status hints) | `AuthView.swift:566, 568, 579` | live validation | monochrome glyph plus accessibility value; drop "Taken" (S5) |
| "Security error. Please try again." | `AuthView.swift:460` | SecRandom failure | keep plus DE |
| "Unexpected credential type." / "Missing identity token." / "Missing nonce. Please try again." | `AuthView.swift:622, 627, 631` | Apple edge cases | collapse to "Sign in with Apple didn't complete. Try again." / "Anmeldung mit Apple nicht abgeschlossen. Bitte erneut versuchen." |
| "Enter your email above, then tap Forgot password." | `AuthView.swift:649` | forgot with no "@" | moves into the reset sheet |
| "Password reset email sent. Check your inbox." (rendered red) | `AuthView.swift:657` | reset ok | neutral style: "If an account exists for {email}, a reset link is on its way." / "Falls ein Konto für {email} existiert, ist ein Link unterwegs." |
| "Incorrect email or password. Please try again." | `AuthService.swift:201` | string match | `invalidCredentials` code |
| "An account with this email already exists. Try signing in instead." | `AuthService.swift:203` | string match | `userAlreadyExists`/`emailExists` |
| "Please check your email to verify your account." | `AuthService.swift:205` | string match | `emailNotConfirmed` |
| "Password must be at least 6 characters." | `AuthService.swift:207` | string match; contradicts the client 8 | `weakPassword` plus server reasons |
| "Something went wrong. Please try again." | `AuthService.swift:209` | everything else, including 429 and Apple cancel | add the rate-limit and link-expired codes (§6.1-3) |
| "No internet connection…" / "The network connection was lost…" / "The request timed out…" / "Can't reach the server right now…" | `AuthService.swift:233, 235, 237, 241` (+ string fallbacks `:248–258`) | URLError chain | keep plus DE |
| "Missing Supabase configuration." | `AuthService.swift:55` | no client | developer-facing; fine |
| "Account deletion failed" | `AuthService.swift:151` | 2xx without success | user-facing rewrite plus DE |
| "Verification failed. Please request a new link." | `SessionController.swift:504` | callback leg failed | split: expired / other device / generic (§5) plus DE |
| "This link doesn't match the account you're signed in to…" (EN/DE) | `SessionController.swift:538–539` | rejected signed-in callback | keep |
| "Missing SUPABASE_URL or SUPABASE_ANON_KEY in configuration" | `AppComposition.swift:131` | build misconfig | developer-facing; fine |
| "Configuration Error" / "KURO" | `KuroApp.swift:142–147` | config error | fine |
| "OFFLINE" | `KuroApp.swift:128` | no network | localize ("OFFLINE" works in both, but use a token style) |
| "Deletion failed" + raw `error.localizedDescription` | `ProfileView.swift:577` | delete error | mapped text plus DE |
| Alert body "This will permanently delete your account…" | `ProfileView.swift:582` | delete confirm | plus DE |
| "Deleting account..." | `ProfileView.swift:586` | in progress | plus DE |

---

## 3. Issue list (severity-ranked)

Severity: CRITICAL / HIGH / MEDIUM / LOW / POLISH. The "BE" column says whether the fix needs a backend or dashboard change.

### 3.1 Security and correctness

| # | Sev | Issue | Evidence | BE |
|---|---|---|---|---|
| S1 | **HIGH** | **Login CSRF / session fixation.** While signed out, any `kuro://auth/callback#access_token=X&refresh_token=Y` is adopted. An attacker sends their own valid token pair as a link. The victim opens it and is silently signed into the attacker's account, and everything they then track, import (AniList/MAL) or post lands in the attacker's account, where the attacker can read it. Since `kuro://` is an unclaimed custom scheme, another installed app could also register it and intercept implicit tokens. | `AuthCallbackGuard.swift:32` (`guard let currentUserId else { return .proceed }`); `SessionController.swift:478–497`; `DeepLinkRouter.swift:64–73`; open item already recorded at `CURRENT_APP_STATE.md:19610`. Tests that pin the current behaviour: `AccountLifecycleTests.swift` decision cases "signed out: other user, future exp -> proceed", "signed out: missing exp -> proceed", "signed out: undecodable token -> proceed" (lines ~563–571). | No |
| S2 | **HIGH** [INFERRED][DASHBOARD?] | **Password reset links are dropped.** `AppComposition.makeClient` builds `SupabaseClientOptions` without `auth:` (`AppComposition.swift:133–139`), so `flowType` is the SDK default `.pkce` (`Defaults.swift:32`, `Types.swift:89`). `resetPasswordForEmail` therefore sends a `code_challenge` and stores a verifier (`AuthClient.swift:1472`, `:1560–1573`). GoTrue then redirects to `kuro://auth/callback?code=…`. `DeepLink.from` returns `nil` unless both `access_token` and `refresh_token` are present (`DeepLinkRouter.swift:70–72`), so `onOpenURL` does nothing: no session, no message. The fallback edge page reads only the hash (`auth-callback/index.ts:252–256`), so it cannot rescue the flow either. CLAUDE.md and `CURRENT_APP_STATE.md:928–931` describe `#access_token` redirects, which contradicts the code. The redirect URL must also be in the dashboard allow-list; otherwise GoTrue redirects to Site URL instead. | as cited | No (client), plus a dashboard check |
| S3 | **HIGH** | **There is no set-new-password step.** Even on an implicit link, `type=recovery` is parsed into the dictionary but discarded (`DeepLinkRouter.swift:16, 73`). `.passwordRecovery` maps to `.other` (`SessionController.swift:333–342`). No call to `auth.update(user: .init(password:))` exists anywhere in `Kuro/` (grep). The reset email promises "Tap the button below to choose a new one" (`reset-password.html`), but the user is just signed in and their password stays unknown to them. | as cited | No |
| S4 | **HIGH** (conditional) | **Sign-in rejects passwords shorter than 8 characters.** `canSubmit` requires `passwordStatus == .valid` (≥8) in both modes (`AuthView.swift:527–534, 558–561`). The server error mapping still reads "Password must be at least 6 characters." (`AuthService.swift:206–207`), and the Supabase default minimum is 6. Accounts created with 6–7 characters can't sign in by email. They see "Password needs at least 8 characters." (`:390–391`), and the reset path is broken (S2/S3). | as cited; **[DASHBOARD?]** current server minimum and whether such accounts exist | No |
| S5 | MEDIUM | **Email enumeration.** `check_email_exists(p_email)` is SECURITY DEFINER over `auth.users`, executable by anon and authenticated, with no rate limit, no auth gate and no captcha (`20260225100000_check_email_exists_rpc.sql:4–19`; `docs/modules/sql-function-index.csv:76` flags `DEFINER_ANON_EXECUTABLE`, `DEFINER_NO_AUTH_GATE_IN_BODY`). Anyone with the public anon key can bulk-test addresses. Under DSGVO, revealing whether a given address has an account is personal data. The UI shows "Taken" (`AuthView.swift:568`). | as cited | **Yes** (revoke/drop migration) |
| S6 | MEDIUM | **Sign-up fails silently when email confirmation is on.** `signUp` returns nil, `authenticate` calls `endSession()` and returns with no error and no message (`SessionController.swift:211–215`; `AuthService.swift:69–75`). The user stays on the form with a cleared spinner. CLAUDE.md still lists "disable email confirmations" as a pending dashboard step. | as cited; **[DASHBOARD?]** | No (client message) |
| S7 | MEDIUM | **Rate limits and server errors show as "Something went wrong."** Mapping is substring matching on `localizedDescription` (`AuthService.swift:199–209`). The SDK's typed `ErrorCode`s are unused (`AuthError.swift`: `overEmailSendRateLimit`, `overRequestRateLimit`, `weakPassword`, `userAlreadyExists`, `emailExists`, `invalidCredentials`, `emailNotConfirmed`, `samePassword`, `otpExpired`, `flowStateExpired`, `flowStateNotFound`, `badCodeVerifier`). With built-in SMTP (about 2 emails per hour per CLAUDE.md), a second "Forgot password?" returns 429 and shows the generic message. The forgot button has no cooldown. | as cited | No |
| S8 | MEDIUM [DASHBOARD?] | **Built-in SMTP can only deliver to team emails** (CLAUDE.md "Custom SMTP (required for production)"). Until Resend SMTP is configured, real users never receive reset emails. | CLAUDE.md Auth section | **Yes** (dashboard) |
| S9 | MEDIUM | **Apple token revocation during deletion is fragile.** `obtainAppleAuthorizationCode` creates a local `ASAuthorizationController` with no `presentationContextProvider`. Its delegate is retained only through an associated object on that same local controller (`ProfileView.swift:650–664`). If the system doesn't retain the controller while the request runs, the continuation never resumes and "Deleting account…" hangs [INFERRED, unverified on device]. If the user cancels, the code is nil, deletion proceeds and revocation is skipped (`handler.ts:60–70`; `adapters.ts:129–185` is best-effort and also skips when Apple env secrets are missing). App Review guideline 5.1.1(v) expects revocation. | as cited | No (client); verify `APPLE_*` secrets are present **[DASHBOARD?]** |
| S10 | LOW | **The fallback edge page moves tokens from the fragment into a query string** (`auth-callback/index.ts:277–280`). Query strings are kept in Safari history and handed to any app that claims `kuro://`. The page has no CSP or `Referrer-Policy`, and it loads Google Fonts. It is not on the current reset path, because `redirectTo` is `kuro://` directly (`AuthService.swift:41, 182`). | as cited | Yes, if kept |
| S11 | LOW | **`AuthCallbackGuard` decodes the JWT without verifying it.** This is documented and fine for the signed-in path, which forces server verification. The signed-out path has no binding at all (that is S1). | `AuthCallbackGuard.swift:22–31` | No |
| S12 | LOW | **Offline presentation restore** shows the stored identity without server validation. This is by design, and private requests still need a real lease (`SessionController.swift:290–297`). Noted only. | as cited | No |
| S13 | INFO | **Nonce generation**: SecRandom bytes map onto a 64-character charset (`AuthView.swift:663–669`). The modulo bias is negligible (256 % 64 = 0, so there is none). SHA-256 is applied for Apple (`:671–673`). OK. | | |

### 3.2 GDPR / DSGVO / store compliance

| # | Sev | Issue | Evidence | BE |
|---|---|---|---|---|
| G1 | MEDIUM | **Terms and Privacy are not links.** "By continuing, you agree to Kuro's Terms of Service and Privacy Policy." is plain `Text` (`AuthView.swift:217–222`, also `:268–273`). No Terms URL exists anywhere in `Kuro/` (grep). The Privacy link appears only after sign-in, in the Profile footer (`ProfileView.swift:690–698` → `https://kuro.app/privacy`; whether that page is live is unknown). | as cited | No (copy); the URLs must exist |
| G2 | MEDIUM | **Google Fonts are loaded from Google** by all 5 email templates (`@import …fonts.googleapis.com` in each `<style>`) and by the edge page (`auth-callback/index.ts:22`). LG München I (3 O 17493/20, 20.01.2022) held that dynamically embedding Google Fonts transmits the IP address without a legal basis. Fix: use the system serif stack (Georgia) or self-host the font. | as cited | **Yes** (templates are pasted in the dashboard; function redeploy) |
| G3 | MEDIUM | **No telemetry disclosure or consent.** `InteractionTelemetry.setUserId(userId)` runs on every `applySession` (`SessionController.swift:654`). `ConciergeAnalytics.flushIfNeeded` runs on reconnect (`KuroApp.swift:178–182`). Nothing at sign-up tells the user. The legal basis (legitimate interest vs consent) is an **open question** for the owner. | as cited | No |
| G4 | LOW | **No age or adult gate at sign-up.** `profiles.adult_opt_in` defaults to false (`AuthService.swift:101–108`). That is acceptable, but onboarding is the natural place for the opt-in and a minimum-age statement. | as cited | No |
| G5 | OK | **Account deletion is reachable in-app** (guideline 5.1.1(v)): Profile → Account → "Delete Account" (`ProfileView.swift:549–557`), with a destructive confirmation alert (`:559–583`). It runs server-side deletion, local sign-out and per-owner local purge (`SessionController.swift:546–593`). **Gaps:** no re-authentication, no German copy, and the error toast shows the raw `localizedDescription` (`ProfileView.swift:577`). | as cited | No |
| G6 | LOW | **No in-app change of password or email.** After S3 is fixed, the same "set password" sheet should be reachable from Profile → Account. | grep | No |

### 3.3 UX, brand, accessibility and adaptivity: AuthView

| # | Sev | Issue | Evidence |
|---|---|---|---|
| U1 | MEDIUM | **Off-brand colours.** The focused field uses blue for label, fill and stroke (`AuthView.swift:488, 510, 517`). The accent red `#A02823` (`:54`) is used for checkmarks (`:572, 583`), the tab underline (`:448`), "Forgot password?" (`:420`) and errors (`:381`). The rulebook says statuses are monochrome and red is for destructive actions only (CLAUDE.md DO-NOT #3; `native-design-polish.md` palette). Ink is a private `#161412` (`:53`) instead of `Color.kuroInk` `#181818` (`KuroDesignSystem.swift:102`). |
| U2 | MEDIUM | **No Dynamic Type.** Every font is `.system(size:)` (e.g. `:180, 185, 200, 305, 315, 323, 404, 418, 445, 487, 498`) instead of the scaled `.kuroX()` roles (`KuroDesignSystem.swift:117–226`). The headline has a hard `\n` (`:184`). |
| U3 | MEDIUM | **Keyboard handling.** `focusedField` is `@State`, set by `.onTapGesture` (`:38, 500`), not `@FocusState`. So focus styling never clears when the keyboard is dismissed, there's no `.submitLabel(.next/.go)` and no `.onSubmit` chain (Return does nothing), no `scrollDismissesKeyboard`, and no tap-outside dismissal. Fields are not disabled while `isWorking`. |
| U4 | MEDIUM | **VoiceOver gaps.** The eye toggle (`:366–371`) and back chevron (`:289–300`) have no `accessibilityLabel`. TextFields have an empty title `""` (`:493, 495`), so VoiceOver relies on the prompt. Status hints "Invalid"/"Taken"/"Min 8" aren't tied to their field. Mode tabs lack `.isSelected` (`:438–455`). Errors aren't announced (`AccessibilityNotification.Announcement`). There are no `.isHeader` traits on "Welcome back" / "Join Kuro". |
| U5 | MEDIUM | **Cancelling Apple sign-in shows an error.** `ASAuthorizationError.canceled` falls into the generic catch, shows "Something went wrong." and forces the email step (`:638–643`). Cancel should be silent and stay on the current step. |
| U6 | MEDIUM | **"Get started" lands on Sign in.** The welcome's primary CTA opens the email step with `mode = .signIn` (`:30, 116–124`), headed "Welcome back / Let's get started". A first-time user expects Create account. |
| U7 | MEDIUM | **Callback errors are lost on the welcome step.** `onChange(of: identity.authErrorMessage)` copies the message into `errorText` and clears it (`:108–113`), but only `emailStep` renders `errorText` (`:378`). A failed or expired link opened while the app sits on the welcome step shows nothing. |
| U8 | MEDIUM | **Success shown as an error.** "Password reset email sent. Check your inbox." goes through `errorText` in red (`:657`). The wording should also be enumeration-safe: "If an account exists for x@y, we've sent a link." |
| U9 | MEDIUM | **No German.** All AuthView strings are English. Onboarding (`OnboardingView.swift:20–23`) and the rejected-callback banner (`SessionController.swift:536–541`) are EN/DE. CLAUDE.md requires correct de_DE handling. |
| U10 | MEDIUM | **Landscape and small phones.** Info.plist allows iPhone landscape (`UISupportedInterfaceOrientations` includes LandscapeLeft/Right). The welcome is a non-scrolling VStack with the banner at `geo.size.height * 0.52` (`:154`), a 33 pt two-line headline and two 54 pt buttons (`:174–227`). At about 390 pt landscape height, or on SE with larger text once U2 is fixed, content collides or clips. Lock the iPhone to portrait or make it a ScrollView with a min-height layout. |
| U11 | LOW | **`DispatchQueue.main.asyncAfter`** in `goToEmail` (`:121`) brings back the pattern CLAUDE.md says was removed on 2026-03-10. Use a cancellable `Task`. |
| U12 | LOW | **Pre-auth network call for a debug-only path.** `.task { await loadCovers() }` (`:100, 593–597`) fetches trending anime anonymously on every Auth appearance, but only the DEBUG `-AuthGenieHero` path uses `coverURLs`. |
| U13 | LOW | **About 650 lines of genie-hero code ship in release** but are reachable only with a DEBUG launch argument (`:229–279`, `:703–1387`). It also contains colourful glows that are off-brand. `MetaballShaders` passes Metal **source** to `ShaderLibrary(data:)`, which expects a compiled metallib, so it likely fails at runtime [INFERRED] (`:1360–1386`). Recommend deleting it or wrapping it in `#if DEBUG`. |
| U14 | LOW | **Copy.** "Your next favorite anime" (`:184`) leaves out manga, which is half the product. "Let's get started" under "Welcome back" (`:321`) is inconsistent. |
| U15 | LOW | **No visible progress for callback processing.** `setSession` runs with no UI feedback. |
| U16 | LOW | **Two different locale checks.** `Locale.current.language` (Onboarding/Profile) vs `Locale.preferredLanguages.first` (`SessionController.swift:111–113`). Pick one helper. |
| U17 | POLISH | The Apple button uses `.white` style plus a hand-drawn stroke (`:212–215, 470`). `.whiteOutline` is the HIG-sanctioned variant. |
| U18 | POLISH | `RootView` bootstrap screen (`KuroApp.swift:155–166`) and empty `UILaunchScreen {}` (Info.plist): launch shows white, then "KURO" + spinner, then the scenery. A branded launch (KuroMark on white) and a cross-fade into the welcome would remove the flash. The "OFFLINE" strip uses `.secondary` and is not localized. |

### 3.4 Onboarding

| # | Sev | Issue | Evidence |
|---|---|---|---|
| O1 | MEDIUM | **Content describes a pager that no longer exists.** With `series_home_native_v1` on, the pager is `[.taste, .home, .discover, .collection, .clubs]` (`ContentView.swift:143–150`) with no Browse. The cards still sell "Browse by genre" and never mention Home (`OnboardingView.swift:155–201`). |
| O2 | MEDIUM | **Visual language.** 80 pt grey circles with SF Symbols (`:213–220`), an 11 pt caption CTA (`:65–75`) and a fixed `maxHeight: 420` TabView (`:43`) that clips at large text sizes. The handoff asks onboarding to reuse the welcome's language (`HANDOFF.md:89`, `native-design-polish.md` "Current design problems"). |
| O3 | MEDIUM | **Completion is per device, not per account.** `UserDefaults.standard "kuro_onboarding_completed"` (`:139, 249–251`): a second account on the same device never sees onboarding, and a reinstall shows it again to an existing user. |
| O4 | MEDIUM | **Collects nothing.** It doesn't ask for medium preference (anime/manga), offer import (AniList/MAL), prime notifications for airing reminders, set the adult opt-in, or link Privacy. Taste Deck is offered only on the last card (`:85–99`). |
| O5 | LOW | **Ignores Reduce Motion.** It uses `KuroAnimation.editorial` / `.fadeIn` directly (`:61, 131`) instead of `KuroMotion.resolve`. |
| O6 | LOW | **Accessibility.** The dot indicator has no accessibility value (`:46–52`). The "Skip" target is caption text with no 44 pt frame (`:78–83, 101–106`). Titles lack `.isHeader`. |
| O7 | LOW | **The `.home` destination doesn't set `selection`** (`ContentView.swift:531–536`). The landing page is whatever the default resolved to: `.discover` (`:153`), or `.home` only once the flag applies (`:338–341`). This is mostly fine but implicit. |

### 3.5 Email templates and edge page

| # | Sev | Issue | Evidence |
|---|---|---|---|
| E1 | MEDIUM | **Brand drift.** Templates use a `#070707` black frame with gold rules `#6b5f4c / #a89878 / #9e8e6e` around a cream `#fcfaf5` card (`reset-password.html` body/table styles). CLAUDE.md documents "warm gray `#f5f5f0`", and the new rulebook is white `#FFFFFF` with `#181818` ink. The edge page is dark `#0a0a0a` (`auth-callback/index.ts:27`). All three disagree. |
| E2 | MEDIUM | **Contrast.** Body and legal text use `rgba(0,0,0,0.10–0.48)` on `#fcfaf5`. For example, "If you didn't request…" is at 0.18 and the expiry note at 0.22. These fail WCAG AA (4.5:1). |
| E3 | LOW | **English only, no imprint or footer.** German law expects an Impressum for commercial communication. Transactional emails are a grey area, so this is recommended rather than required. |
| E4 | LOW | **Edge page dead link.** "Continue in browser" has `href="#"` and is never shown (`index.ts:239`). Messages are English only. |
| E5 | INFO | Templates use `{{ .ConfirmationURL }}` (each file, about line 84), which is compatible with PKCE (GoTrue adds `?code=`). |

---

## 4. Branding consistency with the approved welcome (b943e457)

- **[VERIFIED] Identical scenery.** `git show b943e457:Kuro/Views/AuthView.swift` `AuthSceneryLoop` and current `KuroSceneryLoop` with `tone: .login` match: same `KuroZenMountains` tile at 3:1 (`tileW = h*3`), 34 s period, two tiles, `.saturation(1.02)`, the white gradient `0.04 / 0 / 0.12` and a 30 fps `TimelineView` (`KuroSceneryLoop.swift:24–90`).
- The only behavioural change is a still frame when Reduce Motion, Low Power or an inactive scene applies (`KuroDesignSystem.swift:423–425`). Low Power is read once per body pass, not observed (`KuroSceneryLoop.swift:28–31`); this is minor.
- Welcome composition (`AuthView.swift:174–227`) is unchanged since b943e457 apart from the environment rewiring (diff reviewed).
- **Recommendation: keep the welcome exactly.** Bring the email form, onboarding, bootstrap screen, emails and edge page up to it: white canvas, `kuroInk`, serif display type, black capsule CTA, hairline strokes, and no blue or red accents.

---

## 5. Login-CSRF and password-reset fix (client-only design)

### 5.1 Principle

The device that starts an email-link flow must be the only device that can finish it, and only for that flow type, within its lifetime, once.

- **PKCE gives the server-enforced binding for free.** The code verifier lives in this device's Keychain (`AuthClient.swift:1560–1567`), and `/token?grant_type=pkce` fails without the matching verifier.
- **A local pending-flow record supplies what PKCE redirects don't carry reliably**: the flow type (recovery has no `type` in the PKCE redirect [INFERRED]), the expiry, and UX routing.

### 5.2 Design

1. **`DeepLinkRouter.swift`**
   - Replace `case authCallback(accessToken:refreshToken:)` (`:16`) with `case authCallback(AuthCallbackPayload)`.
   - `AuthCallbackPayload` contains: `code: String?`, `accessToken: String?`, `refreshToken: String?`, `type: String?`, `errorCode: String?`, `errorDescription: String?`.
   - Parse the fragment and the query (`:64–73, 79–100`). Return the payload whenever *any* of `code / access_token / error / error_code` is present, so expired-link errors reach the UI.
   - Fix `parseAuthParams`' `kv.count == 2` split, which drops values that contain `=`. Use `URLComponents` on a synthetic `?` + fragment instead.
2. **New `Kuro/Identity/PendingAuthFlow.swift`** (pure value plus a small store):
   - `struct PendingAuthFlow: Codable { kind: .recovery | .magicLink | .emailChange; emailHash: String (SHA-256 of lowercased, trimmed email); createdAt: Date; expiresAt: Date }`.
   - `expiresAt = createdAt + 3600 s`, matching "This link expires in 1 hour" in the template and the GoTrue OTP default **[DASHBOARD?]**.
   - Storage: `UserDefaults` is enough (not secret; the verifier stays in the SDK Keychain). Keychain is optional.
   - API: `begin(kind:email:)`, `current(now:) -> PendingAuthFlow?` (auto-purges when expired), `consume()`, `clear()`.
   - Single slot, to mirror the SDK's single verifier slot.
3. **`AuthService.resetPassword` (`AuthService.swift:177–183`)**: after a successful `resetPasswordForEmail`, call `PendingAuthFlow.begin(.recovery, email)`. Do the same in any future `signInWithOTP` or `update(user: email)`.
4. **`AuthCallbackGuard.swift:31–40`**: add `pending: PendingAuthFlow?` and `payload` inputs and new decisions:
   - `.exchangeCode(kind)`: signed out, `code` present and a pending flow exists.
   - `.rejectNoPendingFlow`: signed out with no live pending flow. Also covers any signed-out implicit token pair: never adopted (option A). Option B, if implicit must survive, is allowed only when a pending flow exists AND the JWT `email` claim hashes to `pending.emailHash` AND `iat >= pending.createdAt` AND `amr` contains `recovery`/`otp` **[verify on a live token]**. Recommended: option A.
   - `.linkError(code, description)`: an error payload, mapped to "This link has expired. Request a new one."
   - The signed-in branch stays as it is (sub + exp ≥60 s). For a signed-in user with a pending recovery and a `code`, exchange is allowed only for the same user (re-check after the exchange, as in `SessionController.swift:515–524`).
5. **`SessionController.handleAuthCallback` (`:478–532`)**:
   - Take the payload and evaluate the new guard with `PendingAuthFlow.current()`.
   - For `.exchangeCode`, run `try await client.auth.exchangeCodeForSession(authCode: code)` **inside the existing `installCredentials` leg** in place of `setSession` (`:496–500`), so F01/F33 ordering is preserved.
   - Then call `PendingAuthFlow.consume()`. If kind is `.recovery`, set `identity.requiresPasswordUpdate = true` **before** `applySession`, so the root never flashes ContentView.
   - Don't use `client.auth.session(from:)` as the gate. Its `isPKCEFlow` check (`AuthClient.swift:1580–1583`) has an `&&`/`||` precedence bug that admits any `code` regardless of the verifier. The server still rejects a mismatched verifier, but the app shouldn't depend on that branch.
   - Map `flowStateExpired / flowStateNotFound / badCodeVerifier / otpExpired` to "This link has expired or was opened on a different device. Request a new one on this device."
6. **`IdentityStore.swift`**: add `var requiresPasswordUpdate = false`. **It must persist across relaunches.** An in-memory flag alone reopens S3: kill the app between the code exchange and `updatePassword`, and `restoreSession` (`SessionController.swift:243–306`) lands straight in ContentView.
   - Persist it per account in a small `PasswordUpdateRequirement` store (UserDefaults key `kuro_requires_password_update.<userId>`, not secret).
   - Write it **before** `applySession` in the exchange path.
   - Clear it only after a successful `updatePassword`, or in sign-out/deletion (`SessionController.swift:595–619, 546–593`). `endSessionState` (`:695–711`) resets only the in-memory copy.
   - Re-read it in `applySession` (`:633–671`), so restore, offline restore and `.initialSession` all set `identity.requiresPasswordUpdate` for that userId.
7. **`KuroApp.swift` `RootView` (`:155–174`)**: add a branch before `ContentView`: `else if identity.isAuthenticated && identity.requiresPasswordUpdate { SetNewPasswordView() }`.
8. **`AuthService.updatePassword(_:)`** (new): `try await client.auth.update(user: UserAttributes(password: new))`. Map `samePassword` and `weakPassword`. On success, clear the flag and show the banner "Password updated."
9. **New view `Kuro/Views/SetNewPasswordView.swift`**: brand form (see §6.2). It shows the same password rules as sign-up and offers "Sign out" as the escape.
10. **Clear `PendingAuthFlow`** on sign-out and deletion (`SessionController.swift:595–619, 546–593`). Leave it alone on a failed sign-in.
11. **Edge page** (if kept): forward `?code=` and the error params unchanged (no token relay). Otherwise delete it and remove it from the docs.
12. **Universal links (later, needs AASA on kuro.app)**: move `redirectTo` to `https://kuro.app/auth/callback` so no other app can claim the scheme. `Kuro.entitlements` already lists `applinks:kuro.app` as a placeholder.

### 5.3 Exact code sites

| Change | Site |
|---|---|
| Payload enum and parsing | `Kuro/Services/DeepLinkRouter.swift:16, 29–30, 64–73, 79–100` |
| URL handling | `Kuro/KuroApp.swift:83–99` (pass the payload; also present a "Signing you in…" overlay) |
| Guard decisions | `Kuro/Identity/AuthCallbackGuard.swift:10–40` |
| Funnel | `Kuro/Identity/SessionController.swift:478–532` (exchange leg, consume, recovery flag), `:536–542` (message variants EN/DE), `:595–619` and `:546–593` (clear pending) |
| Transport | `Kuro/Identity/AuthService.swift:177–183` (begin pending), new `updatePassword`, error mapping `:187–210` → `AuthError.errorCode` switch |
| Identity | `Kuro/Identity/IdentityStore.swift:20–27` (`requiresPasswordUpdate`), plus a persisted per-user requirement read in `SessionController.applySession` (`:633–671`) |
| Root gate | `Kuro/KuroApp.swift:155–174` |
| New files | `Kuro/Identity/PendingAuthFlow.swift`, `Kuro/Views/SetNewPasswordView.swift` (add to the target; update file counts in docs) |
| Tests to flip or add | `KuroTests/AccountLifecycleTests.swift` cases "signed out: … -> proceed" (×3, ~563–571) → `.rejectNoPendingFlow`. New: pending+code → exchange (stub `/token?grant_type=pkce`); expired pending → reject; error payload → message; recovery → `requiresPasswordUpdate`; **the recovery requirement survives a relaunch (restore → SetNewPasswordView, not ContentView)**; a successful `updatePassword` clears it; sign-out clears pending and the requirement. Keep `IdentityCompositionTests.swift:662–682` (same-user, signed-in) and `:925–940` (foreign while signed in), adjusted to the payload type. Add `DeepLink.from` tests for `?code=`, `#error=…`, and values containing `=`. |

### 5.4 Trade-offs

- A link opened on another device (requested on the iPhone, opened on a Mac or iPad) is rejected. The copy explains this. This is the intended security property.
- A second "Forgot password" overwrites the verifier (single SDK slot), so only the newest email works. The copy says "Use the most recent email."
- Implicit-token links stop working entirely while signed out. Nothing legitimate produces them once the client is PKCE (the default).

---

## 6. Fix and polish plan (ordered)

### 6.1 P0: correctness and security (client-only, no deploy)
1. §5 in full: the CSRF fix, PKCE reset routing, and the set-new-password screen.
2. **Sign-in has no length rule.** In `canSubmit` (`AuthView.swift:527–534`), sign-in requires only a non-empty password. Sign-up keeps ≥8 (and the server minimum should be raised to 8 **[DASHBOARD]**). Make `AuthService.swift:206–207` match.
3. **Typed error mapping.** Switch on `(error as? AuthError)?.errorCode` before string matching. Messages, EN/DE:
   - `invalidCredentials` → "Incorrect email or password."
   - `userAlreadyExists` / `emailExists` → "An account with this email already exists. Sign in instead." (then switch the tab)
   - `weakPassword` → server reasons
   - `overEmailSendRateLimit` → "Too many emails requested. Try again in a few minutes." (and start a 60 s cooldown on the button)
   - `overRequestRateLimit` → "Too many attempts. Wait a moment and try again."
   - `emailNotConfirmed` → "Confirm your email first."
   - link codes as in §5.
4. **Sign-up with no session (S6)**: show "Check your inbox to confirm your email." instead of silence (`SessionController.swift:211–215` → surface an `AuthOutcome.needsConfirmation`).
5. **Apple cancel (U5)**: `if (error as? ASAuthorizationError)?.code == .canceled { return }` (`AuthView.swift:638`). Don't change step.
6. **Callback errors on the welcome step (U7)**: render errors on both steps, or auto-advance to the email step when an auth error arrives.

### 6.2 P1: brand, accessibility and adaptivity on AuthView (no deploy)
- **Tokens**:
  - Replace `Self.ink`/`Self.accent` and the blue focus colours with `Color.kuroInk`, `kuroInkSecondary`, `kuroInkQuiet` and `kuroHairline`.
  - Focus state: `kuroInk` 1.5 pt stroke on a `#F6F6F6` quiet surface.
  - Valid state: monochrome `checkmark` in `kuroInkSecondary`.
  - Errors: `kuroInk` text with an `exclamationmark.circle` glyph. If a colour is needed, `kuroError` only for blocking failures; never for links or success.
  - Tab underline: `kuroInk`.
  - "Forgot password?": `kuroInkSecondary` underline.
- **Typography**: `.kuroDisplay`/`.kuroFeature` for the headline (serif), `.kuroBody` for fields and buttons, `.kuroCaption` for legal text. Drop the hard `\n` and let text wrap.
- **Focus**:
  - Use `@FocusState private var focusedField: Field?`, binding with `.focused($focusedField, equals:)`.
  - Email: `.submitLabel(.next)` with `.onSubmit { focusedField = .password }`. Password: `.submitLabel(.go)` with `.onSubmit { submit }`.
  - Add `.scrollDismissesKeyboard(.interactively)`, and disable fields while `isWorking`.
- **Accessibility**:
  - Labels: "Show password"/"Hide password", "Back".
  - `.accessibilityValue` for field status. `.isSelected` on tabs. `.isHeader` on titles.
  - Announce errors with `AccessibilityNotification.Announcement(errorText).post()`.
  - Keep 44 pt targets.
- **Adaptivity**: wrap the welcome chrome in a `ViewThatFits` or a ScrollView whose min height is the container height. Either lock the iPhone to portrait (Info.plist) or design landscape (banner 40%, side-by-side chrome). Recommended: lock portrait on iPhone; iPad keeps all orientations.
- **Flow**:
  - "Get started" opens **Create account**.
  - Add a secondary text button "I already have an account" on the welcome, which opens Sign in.
  - Sign-in subtitle: "Pick up where you left off." Sign-up: "Create your shelf."
  - Welcome copy: "Your next favourite anime and manga, already waiting." (needs owner sign-off) plus a DE translation.
- **Legal**: make the line an `AttributedString` with `Link`s to `https://kuro.app/terms` and `https://kuro.app/privacy` (presented via `SFSafariViewController` or an in-app sheet). Add "We use privacy-friendly usage analytics." with a link (see G3).
- **Forgot password**: use a dedicated sheet ("Reset password", email field prefilled, "Send link"). On success, show a neutral confirmation with the enumeration-safe wording and a 60 s resend cooldown.
- **Engineering**: replace `DispatchQueue.main.asyncAfter` (`:121`) with `Task { try? await Task.sleep(...) }` stored and cancelled. Remove `loadCovers` (`:100, 593–597`). Delete the genie hero or wrap it in `#if DEBUG` (`:229–279, 703–1387`).
- **Localization**: add EN/DE for every AuthView string, using the same locale helper as `SessionController` (one shared `KuroLocale.isGerman`).

### 6.3 P1: onboarding redesign (no deploy)
Goal: 3–4 calm steps in the welcome's visual language that collect useful intent and end on a real first action.

1. **Arrival**: the scenery (`KuroSceneryLoop`, `.login` tone, `isActive` bound to the step) with the serif headline "Welcome to Kuro". One line: "A quiet place for the anime and manga you love."
2. **What do you follow?**: Anime / Manga / Both, as large poster-capsule toggles. Persist it to Home's medium choice (`home.medium`) for this account.
3. **Bring your list**: AniList / MAL / MAL XML via the existing source chooser (`ImportWorkflowSheet`, per `native-design-polish.md` "Actions"). Show "Skip for now".
4. **Teach Kuro your taste**: opens the Taste Deck (existing flag `tasteDeckV1Enabled`), or "Start exploring" which lands on Home/Discover explicitly.
5. **Optional contextual primer** for airing reminders (not at first launch; when the first title is tracked).

- **Mechanics**:
  - Key completion per account: `kuro_onboarding_completed.<userId>`. Show onboarding only after **sign-up**, or for accounts with zero library entries.
  - Use `KuroMotion.resolve` for every animation and a ScrollView or `ViewThatFits` instead of `maxHeight: 420`.
  - Primary CTA uses `.kuroBody(.medium)` at 17 pt in a 54 pt capsule, matching the welcome. "Skip" gets a 44 pt target.
  - Add a dot indicator accessibility value ("Step 2 of 4").
  - Set `selection` explicitly on completion (`ContentView.swift:531–536`).

### 6.4 P1: bootstrap and launch
- Set `UILaunchScreen` to a white background with a `KuroMark` image (Info.plist `UIImageName`).
- `RootView` bootstrap: the same mark centred, with a cross-fade into the welcome or content (`KuroApp.swift:155–166`).
- Localize "OFFLINE".

### 6.5 P2: backend and dashboard (needs deploy or dashboard; out of this lane's write scope)
- **S5**: a migration that `REVOKE EXECUTE ON FUNCTION public.check_email_exists(text) FROM anon, authenticated;` and later drops it. The client stops calling it: sign-up relies on the `userAlreadyExists`/`emailExists` error from `signUp`. With confirmations off, GoTrue returns that error, which still enumerates but is rate-limited by GoTrue. Removing the RPC removes the unthrottled oracle.
- **Dashboard**: minimum password length 8, plus leaked-password protection if on a paid plan; confirm the email-confirmation setting; add `kuro://auth/callback` (and later `https://kuro.app/auth/callback`) to Redirect URLs; Resend SMTP; OTP expiry = 3600 s; `APPLE_CLIENT_ID`/`APPLE_CLIENT_SECRET` secrets for revocation.
- **Emails**: re-skin all 5 to white `#FFFFFF` with `#181818` ink and a hairline frame, and drop the black/gold frame. Body text must be at least `#5C5C5C`. Use the Georgia/system serif stack (no Google Fonts). Provide EN/DE variants, or bilingual copy, since Supabase templates are single-language. Add an imprint footer line.
- **Edge page**: either delete `auth-callback` or re-skin it to light. Forward `?code=` and error params only, add CSP `default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'` and `Referrer-Policy: no-referrer`, and remove Google Fonts and the dead link.

### 6.6 P2: deletion polish
- Give the Apple code request a `presentationContextProvider` (key window), and retain the controller and delegate in a `@State`/actor holder with a timeout, so the continuation always resumes.
- Copy: "We couldn't revoke Sign in with Apple. Remove Kuro in Settings › Apple ID › Sign-In & Security." shown when the code is nil.
- EN/DE alert copy. Map deletion errors to user-facing text instead of the raw `localizedDescription` (`ProfileView.swift:577`).
- Optional: re-authentication or typed confirmation ("DELETE") for accounts with a library.

---

## 7. Verification checklist for the implementing lane

- `xcodebuild … test -only-testing:KuroTests`: the three flipped guard cases, the new PKCE/pending tests and the DeepLink parsing tests pass.
- `scripts/quality-gates/check_architecture.sh`: there's no SDK import in `SetNewPasswordView`; the transport stays in `AuthService`.
- Simulator, reset flow: request a reset, open `kuro://auth/callback?code=<fake>` with no pending flow and expect a rejection message. With a pending flow and a stubbed `/token`, the set-password screen should appear. Open `kuro://auth/callback#access_token=…` while signed out and expect a rejection with no session.
- Simulator a11y: VoiceOver walk of welcome, email, set-password and onboarding; Dynamic Type at AX3; SE (375×667) and Pro Max portrait; landscape locked.
- Docs: update `CURRENT_APP_STATE.md` §auth (PKCE, no implicit tokens), `CURRENT_APP_STATE_PLAIN.md`, CLAUDE.md "Auth Email Flow", and the file counts.

---

## 8. Open questions (dashboard or owner facts not in the repo)

1. Is `kuro://auth/callback` in the Auth **Redirect URLs** allow-list, and what is **Site URL**?
2. What is the current **minimum password length**, and do accounts with 6–7 character passwords exist?
3. Is **"Enable email confirmations"** actually OFF in production (CLAUDE.md lists it as pending)?
4. Is **custom SMTP (Resend)** configured? If not, reset email reaches team addresses only.
5. **Email OTP/link expiry** (the template says 1 hour).
6. Are `https://kuro.app/privacy` and a Terms page live? Who owns the legal copy (DE/EN), and what is the telemetry legal basis (consent vs legitimate interest)?
7. Are `APPLE_CLIENT_ID` / `APPLE_CLIENT_SECRET` set on `delete-account` (revocation silently skips otherwise, `adapters.ts:135–137`)?
8. Should onboarding show for existing users on a new device, or only after sign-up / for empty libraries?
9. Is the `auth-callback` edge function still wanted, or can it be retired?
