// Review-only layouts. Instrument remains responsible for mutations and detail routing.
(() => {
  const names = ['library', 'chapterboard', 'journal', 'clubroom'];
  let currentUI = null;
  const e = value => currentUI.escape(value);
  const picture = (key, extra = '') => `<button class="mp-art" data-detail="${key}" aria-label="Open ${e(currentUI.get(key).title)}" ${extra}>${currentUI.art(key)}</button>`;
  const heading = key => `<h2 class="mp-title">${currentUI.title(key)}</h2>`;
  const position = key => currentUI.position(key);
  const tile = (key, kind) => `<article class="mp-item ${kind}" data-active="${key}">${picture(key)}${kind === 'board-cell' ? `<div class="board-metric" data-board-metric="${key}">${position(key).max !== null ? `<b>${Math.max(0, position(key).max - position(key).n)}</b><span>to read</span>` : '<span class="board-unknown">Total<br>pending</span>'}</div>` : ''}${heading(key)}<div class="mp-progress">${currentUI.progress(key)}</div><div class="mp-context">${currentUI.context(key, true)}</div></article>`;
  window.KURO_MANGA_PHILOSOPHIES = {
    names,
    render(name, list, ui) {
      currentUI = ui;
      if (name === 'library') {
        return `<div class="mp-library mp-root"><div class="library-covers" role="group" aria-label="Your current reads">${list.map(key => `<article class="library-object" data-active="${key}"><button class="library-story" data-detail="${key}" aria-label="Open ${e(ui.get(key).title)} details"><span class="library-art">${ui.art(key)}</span><span class="mp-title library-title">${e(ui.get(key).title)}</span></button><div class="library-reading-actions">${ui.progress(key)}</div></article>`).join('')}</div></div>`;
      }
      if (name === 'chapterboard') return `<div class="mp-board mp-root">${list.map(key => tile(key, 'board-cell')).join('')}</div>`;
      if (name === 'journal') {
        // Explicit preview-only recency. Never derive last-read timestamps from a cover or ID.
        const recency = [['Last opened', list.slice(0, 2)], ['Earlier this week', list.slice(2, 4)], ['Still in rotation', list.slice(4)]];
        return `<div class="mp-journal mp-root">${recency.filter(([, keys]) => keys.length).map(([label, keys]) => `<section class="journal-entry"><h2 class="journal-date">${label}</h2>${keys.map(key => tile(key, 'journal-line')).join('')}</section>`).join('')}</div>`;
      }
      const shared = list.filter(key => position(key).readers.length);
      const personal = list.filter(key => !position(key).readers.length);
      return `<div class="mp-clubroom mp-root"><section class="clubroom-table" aria-label="Your current reads shared with Sunday Club"><header class="clubroom-heading"><span class="clubroom-members" aria-hidden="true"><i>M</i><i>J</i><i>A</i></span><div><span class="clubroom-eyebrow">READING TOGETHER</span><h2>Sunday Club</h2></div><span class="clubroom-private" aria-label="Private club"><svg viewBox="0 0 20 20"><rect x="5" y="8" width="10" height="9" rx="2"/><path d="M7 8V5a3 3 0 0 1 6 0v3"/></svg></span></header><div class="clubroom-reads">${shared.map(key => tile(key, 'clubroom-seat')).join('')}</div></section><section class="clubroom-personal"><h2 class="mp-section-title">Your own pace.</h2><div class="clubroom-reads">${personal.map(key => tile(key, 'clubroom-seat')).join('')}</div></section></div>`;
    },
    sync() {
      if (!currentUI) return;
      document.querySelectorAll('[data-board-metric]').forEach(el => { const p = position(el.dataset.boardMetric); if (p.max !== null) el.querySelector('b').textContent = Math.max(0, p.max - p.n); });

    }
  };
})();
