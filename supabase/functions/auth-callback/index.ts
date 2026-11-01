import "jsr:@supabase/functions-js/edge-runtime.d.ts";

/**
 * Auth Callback — fallback redirect page for Supabase email links.
 *
 * The app's own redirect is `kuro://auth/callback` (AuthService.authCallbackURL), so this page is only
 * used when a link is configured to land on the web first. It forwards the link into the app
 * unchanged and holds nothing itself:
 *   - PKCE (`?code=…`, the SDK default) and error parameters (`error`, `error_code`,
 *     `error_description`) are forwarded as query parameters, allow-listed;
 *   - an implicit-flow fragment (`#access_token=…`) is forwarded as a fragment, never moved into a
 *     query string (query strings end up in history and in any app that claims the scheme).
 * The app accepts a link only for a flow it started on that device (spec D12).
 *
 * 2026-11-01 re-skin (prepared, NOT deployed): white page and #181818 ink to match the app's welcome,
 * system fonts only (no Google Fonts request), EN/DE copy, strict CSP with a per-request script nonce,
 * `Referrer-Policy: no-referrer`, no dead "continue in browser" link, reduced motion respected.
 *
 * Deployed with verify_jwt=false since this is a public redirect endpoint.
 */

const FORWARDED_QUERY_KEYS = [
  "code",
  "type",
  "error",
  "error_code",
  "error_description",
];

function page(nonce: string): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta name="color-scheme" content="light">
<meta name="referrer" content="no-referrer">
<title>Kuro</title>
<style>
  *, *::before, *::after { margin: 0; padding: 0; box-sizing: border-box; }
  :root {
    --page: #ffffff;
    --ink: #181818;
    --ink-secondary: #5c5c5c;
    --ink-quiet: #6b6b6b;
    --hairline: rgba(0, 0, 0, 0.10);
    --serif: Georgia, 'Times New Roman', Times, serif;
    --sans: -apple-system, BlinkMacSystemFont, 'Helvetica Neue', Helvetica, Arial, sans-serif;
  }
  html, body { min-height: 100%; background: var(--page); color: var(--ink); font-family: var(--sans);
    -webkit-font-smoothing: antialiased; }
  main { min-height: 100vh; display: flex; flex-direction: column; justify-content: center;
    max-width: 440px; margin: 0 auto; padding: 48px 28px; }
  .mark { font-family: var(--serif); font-weight: 700; font-size: 20px; letter-spacing: 4px; color: var(--ink); opacity: 0.72; }
  h1 { font-family: var(--serif); font-weight: 400; font-size: 34px; line-height: 1.2; margin-top: 28px; }
  .rule { width: 46px; height: 2px; background: var(--ink); margin-top: 16px; }
  p { font-size: 17px; line-height: 1.55; color: var(--ink-secondary); margin-top: 16px; }
  .cta { display: none; margin-top: 32px; padding: 16px 24px; min-height: 52px; border-radius: 999px;
    background: var(--ink); color: #ffffff; font-size: 17px; font-weight: 600; text-align: center;
    text-decoration: none; -webkit-tap-highlight-color: transparent; }
  .cta.visible { display: block; }
  .cta:active { background: #2e2e2e; transform: scale(0.98); }
  .note { font-size: 13px; color: var(--ink-quiet); margin-top: 20px; }
  main > * { animation: rise 280ms ease-out both; }
  @keyframes rise { from { opacity: 0; transform: translateY(6px); } to { opacity: 1; transform: none; } }
  @media (prefers-reduced-motion: reduce) { main > * { animation: none; } .cta:active { transform: none; } }
</style>
</head>
<body>
<main>
  <div class="mark" aria-hidden="true">Kuro</div>
  <h1 id="title">Opening Kuro</h1>
  <div class="rule" aria-hidden="true"></div>
  <p id="message" role="status">One moment.</p>
  <a class="cta" id="cta" href="kuro://">Open Kuro</a>
  <p class="note" id="note"></p>
</main>
<script nonce="${nonce}">
(function () {
  var german = (navigator.language || '').toLowerCase().indexOf('de') === 0;
  if (german) { document.documentElement.lang = 'de'; }
  function t(en, de) { return german ? de : en; }

  var query = new URLSearchParams(window.location.search);
  var hash = window.location.hash || '';
  var hashParams = new URLSearchParams(hash.charAt(0) === '#' ? hash.substring(1) : hash);
  var forwarded = new URLSearchParams();
  ${JSON.stringify(FORWARDED_QUERY_KEYS)}.forEach(function (key) {
    var value = query.get(key);
    if (value) { forwarded.set(key, value); }
  });
  var search = forwarded.toString();
  var target = 'kuro://auth/callback' + (search ? '?' + search : '') + (hash.length > 1 ? hash : '');

  var failed = forwarded.has('error') || forwarded.has('error_code') || hashParams.has('error') || hashParams.has('error_code');
  var hasLink = forwarded.has('code') || hashParams.has('access_token');
  var type = forwarded.get('type') || hashParams.get('type') || '';

  var title = document.getElementById('title');
  var message = document.getElementById('message');
  var cta = document.getElementById('cta');
  var note = document.getElementById('note');
  cta.textContent = t('Open Kuro', 'Kuro öffnen');
  note.textContent = t('Open this link on the device where you asked for it.',
                       'Öffne diesen Link auf dem Gerät, auf dem du ihn angefordert hast.');

  if (failed) {
    title.textContent = t('This link has expired', 'Dieser Link ist abgelaufen');
    message.textContent = t('Request a new one in Kuro and use the most recent email.',
                            'Fordere in Kuro einen neuen an und nutze die neueste E-Mail.');
  } else if (type === 'recovery') {
    title.textContent = t('Choose a new password', 'Wähle ein neues Passwort');
    message.textContent = t('Kuro opens on the screen for your new password.',
                            'Kuro öffnet sich auf dem Bildschirm für dein neues Passwort.');
  } else {
    title.textContent = t('Opening Kuro', 'Kuro wird geöffnet');
    message.textContent = t('One moment.', 'Einen Moment.');
  }

  cta.setAttribute('href', hasLink || failed ? target : 'kuro://');
  if (hasLink || failed) {
    setTimeout(function () { window.location.href = target; }, 400);
  }
  // Still here (the app did not open): offer the button.
  setTimeout(function () { cta.classList.add('visible'); }, hasLink ? 2500 : 0);
})();
</script>
</body>
</html>`;
}

Deno.serve((_req: Request) => {
  const nonce = crypto.randomUUID().replace(/-/g, "");
  return new Response(page(nonce), {
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store, no-cache, must-revalidate",
      "Content-Security-Policy":
        `default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-${nonce}'; img-src 'none'; ` +
        "base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
      "Referrer-Policy": "no-referrer",
      "X-Frame-Options": "DENY",
      "X-Content-Type-Options": "nosniff",
    },
  });
});
