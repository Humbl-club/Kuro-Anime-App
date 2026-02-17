import "jsr:@supabase/functions-js/edge-runtime.d.ts";

/**
 * Auth Callback — Redirect page for Supabase email verification flows.
 *
 * After Supabase verifies an email token (signup, recovery, magic link, etc.),
 * it redirects here with session tokens in the URL hash fragment.
 * This page attempts to deep-link into the Kuro iOS app, falling back to
 * a beautiful confirmation page with a manual "Open Kuro" button.
 *
 * Deployed with verify_jwt=false since this is a public redirect endpoint.
 */

Deno.serve((_req: Request) => {
  const html = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<title>Kuro</title>
<style>
  @import url('https://fonts.googleapis.com/css2?family=Cormorant:ital,wght@0,300;0,400;0,500;0,600;1,300&display=swap');

  *, *::before, *::after { margin: 0; padding: 0; box-sizing: border-box; }

  :root {
    --bg: #0a0a0a;
    --fg: #f5f5f0;
    --fg-dim: rgba(245,245,240,0.45);
    --fg-muted: rgba(245,245,240,0.22);
    --accent: #f5f5f0;
    --serif: 'Cormorant', Georgia, 'Times New Roman', serif;
    --sans: -apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif;
  }

  html, body {
    height: 100%;
    background: var(--bg);
    color: var(--fg);
    font-family: var(--sans);
    -webkit-font-smoothing: antialiased;
    -moz-osx-font-smoothing: grayscale;
    overflow: hidden;
  }

  /* Grain overlay */
  body::before {
    content: '';
    position: fixed;
    inset: 0;
    z-index: 100;
    pointer-events: none;
    opacity: 0.035;
    background-image: url("data:image/svg+xml,%3Csvg viewBox='0 0 256 256' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='4' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E");
    background-size: 200px 200px;
  }

  .container {
    height: 100%;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    padding: 40px 32px;
    position: relative;
  }

  /* Subtle radial glow behind logo */
  .container::before {
    content: '';
    position: absolute;
    width: 320px;
    height: 320px;
    border-radius: 50%;
    background: radial-gradient(circle, rgba(245,245,240,0.03) 0%, transparent 70%);
    top: 50%;
    left: 50%;
    transform: translate(-50%, -60%);
    pointer-events: none;
  }

  /* Logo mark */
  .logo {
    font-family: var(--serif);
    font-weight: 300;
    font-size: 72px;
    letter-spacing: 0.15em;
    line-height: 1;
    opacity: 0;
    transform: translateY(12px) scale(0.96);
    animation: fadeUp 1s cubic-bezier(0.16, 1, 0.3, 1) 0.2s forwards;
    position: relative;
    z-index: 1;
  }

  /* Thin rule */
  .rule {
    width: 36px;
    height: 1px;
    background: var(--fg-muted);
    margin: 28px 0;
    opacity: 0;
    animation: fadeIn 0.8s ease 0.6s forwards;
  }

  /* Status heading */
  .status {
    font-family: var(--sans);
    font-size: 11px;
    font-weight: 500;
    letter-spacing: 0.22em;
    text-transform: uppercase;
    color: var(--fg-dim);
    opacity: 0;
    transform: translateY(8px);
    animation: fadeUp 0.8s cubic-bezier(0.16, 1, 0.3, 1) 0.8s forwards;
    text-align: center;
  }

  /* Subtitle */
  .subtitle {
    font-family: var(--serif);
    font-weight: 300;
    font-style: italic;
    font-size: 18px;
    color: var(--fg-dim);
    margin-top: 14px;
    opacity: 0;
    transform: translateY(8px);
    animation: fadeUp 0.8s cubic-bezier(0.16, 1, 0.3, 1) 1s forwards;
    text-align: center;
    line-height: 1.5;
  }

  /* Loading dots */
  .dots {
    display: flex;
    gap: 6px;
    margin-top: 32px;
    opacity: 0;
    animation: fadeIn 0.6s ease 1.2s forwards;
    transition: opacity 0.4s ease;
  }
  .dots.hidden { opacity: 0 !important; }
  .dot {
    width: 3px;
    height: 3px;
    border-radius: 50%;
    background: var(--fg-dim);
    animation: pulse 1.4s ease-in-out infinite;
  }
  .dot:nth-child(2) { animation-delay: 0.15s; }
  .dot:nth-child(3) { animation-delay: 0.3s; }

  /* CTA button (hidden initially, shown as fallback) */
  .cta {
    display: none;
    margin-top: 36px;
    padding: 14px 42px;
    font-family: var(--sans);
    font-size: 11px;
    font-weight: 600;
    letter-spacing: 0.2em;
    text-transform: uppercase;
    text-decoration: none;
    color: var(--bg);
    background: var(--accent);
    border: none;
    border-radius: 0;
    cursor: pointer;
    transition: all 0.25s ease;
    opacity: 0;
    transform: translateY(8px);
    -webkit-tap-highlight-color: transparent;
  }
  .cta.visible {
    display: block;
    animation: fadeUp 0.6s cubic-bezier(0.16, 1, 0.3, 1) forwards;
  }
  .cta:hover { background: rgba(245,245,240,0.85); }
  .cta:active { transform: translateY(0) scale(0.97); }

  /* Secondary link */
  .secondary {
    display: none;
    margin-top: 16px;
    font-size: 11px;
    letter-spacing: 0.08em;
    color: var(--fg-muted);
    text-decoration: none;
    transition: color 0.2s;
    opacity: 0;
    transform: translateY(6px);
  }
  .secondary.visible {
    display: block;
    animation: fadeUp 0.5s cubic-bezier(0.16, 1, 0.3, 1) 0.15s forwards;
  }
  .secondary:hover { color: var(--fg-dim); }

  /* Footer */
  .footer {
    position: absolute;
    bottom: 32px;
    left: 50%;
    transform: translateX(-50%);
    font-size: 10px;
    letter-spacing: 0.12em;
    color: var(--fg-muted);
    opacity: 0;
    animation: fadeIn 0.6s ease 1.4s forwards;
    white-space: nowrap;
  }

  @keyframes fadeUp {
    to { opacity: 1; transform: translateY(0) scale(1); }
  }
  @keyframes fadeIn {
    to { opacity: 1; }
  }
  @keyframes pulse {
    0%, 100% { opacity: 0.3; transform: scale(1); }
    50% { opacity: 1; transform: scale(1.3); }
  }
</style>
</head>
<body>
<div class="container">
  <div class="logo">K</div>
  <div class="rule"></div>
  <div class="status" id="status">Verifying</div>
  <div class="subtitle" id="subtitle">One moment&hellip;</div>
  <div class="dots" id="dots">
    <span class="dot"></span>
    <span class="dot"></span>
    <span class="dot"></span>
  </div>
  <a class="cta" id="cta" href="#">Open Kuro</a>
  <a class="secondary" id="secondary" href="#">Continue in browser</a>
  <div class="footer">KURO &mdash; Curated Anime &amp; Manga</div>
</div>

<script>
(function() {
  const statusEl = document.getElementById('status');
  const subtitleEl = document.getElementById('subtitle');
  const dotsEl = document.getElementById('dots');
  const ctaEl = document.getElementById('cta');
  const secondaryEl = document.getElementById('secondary');

  // Read tokens from URL hash fragment (set by Supabase after token verification)
  const hash = window.location.hash.substring(1);
  const params = new URLSearchParams(hash);
  const type = params.get('type') || 'signup';
  const accessToken = params.get('access_token');
  const refreshToken = params.get('refresh_token');

  // Type-specific messaging
  const messages = {
    signup:       { status: 'Email Verified',    subtitle: 'Welcome to Kuro' },
    recovery:     { status: 'Identity Confirmed', subtitle: 'Set your new password in the app' },
    magiclink:    { status: 'Link Verified',     subtitle: 'Signing you in' },
    email_change: { status: 'Email Updated',     subtitle: 'Your new email is confirmed' },
    invite:       { status: 'Invitation Accepted', subtitle: 'Welcome aboard' },
  };

  const msg = messages[type] || messages.signup;

  // Update UI after initial animation
  setTimeout(function() {
    statusEl.textContent = msg.status;
    subtitleEl.textContent = msg.subtitle;
  }, 1600);

  if (accessToken && refreshToken) {
    // Build deep link with tokens
    var deepLink = 'kuro://auth/callback?access_token=' +
      encodeURIComponent(accessToken) +
      '&refresh_token=' + encodeURIComponent(refreshToken) +
      '&type=' + encodeURIComponent(type);

    // Attempt app redirect after animation settles
    setTimeout(function() {
      window.location.href = deepLink;
    }, 2200);

    // If still here after 4s, show fallback button
    setTimeout(function() {
      dotsEl.classList.add('hidden');
      subtitleEl.textContent = msg.subtitle;
      ctaEl.href = deepLink;
      ctaEl.classList.add('visible');
    }, 4000);
  } else {
    // No tokens — just show confirmation + open app button
    setTimeout(function() {
      dotsEl.classList.add('hidden');
      ctaEl.href = 'kuro://';
      ctaEl.classList.add('visible');
    }, 2500);
  }
})();
</script>
</body>
</html>`;

  return new Response(html, {
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'no-store, no-cache, must-revalidate',
      'X-Frame-Options': 'DENY',
      'X-Content-Type-Options': 'nosniff',
    },
  });
});
