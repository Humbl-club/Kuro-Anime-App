// Local Home compositions. Existing Instrument owns all progress, details and club actions.
// No new account, API, persistence or release data is introduced by this renderer.
window.KURO_MANGA_DIRECTIONS = {
  names: ['edition', 'contact', 'index', 'crosscut'],
  render(direction, list, ui) {
    const { art, title, progress, context, material, escape, get } = ui;
    if (direction === 'crosscut') {
      // A chapter sits in the gutter cut out of the image, rather than on a second card.
      // DOM order is reading order; alternating panel widths never reorder the titles.
      const panel = (key, index) => `<article class="crosscut-panel" data-active="${key}" data-slot="${index}" style="${material(key)}">
        <div class="crosscut-window">
          <button class="crosscut-art" data-detail="${key}" aria-label="Open ${escape(get(key).title)}">${art(key)}</button>
          <div class="crosscut-cursor">${progress(key)}</div>
        </div>
        <h2 class="crosscut-title">${title(key)}</h2>
        <div class="crosscut-context">${context(key, true)}</div>
      </article>`;
      return `<div class="crosscut-page" aria-label="Your current reads">${Array.from({ length: Math.ceil(list.length / 2) }, (_, pair) => `<div class="crosscut-pair">${list.slice(pair * 2, pair * 2 + 2).map((key, offset) => panel(key, pair * 2 + offset)).join('')}</div>`).join('')}</div>`;
    }
    const image = key => `<button class="cover reading-study-cover" data-detail="${key}" aria-label="Open ${escape(get(key).title)}">${art(key)}</button>`;
    const item = (key, index, kind) => `<article class="reading-study-item ${kind}" data-active="${key}" data-slot="${index}" style="${material(key)}">
      <div class="reading-study-art">${image(key)}</div>
      <div class="reading-study-title"><h2>${title(key)}</h2></div>
      <div class="reading-study-progress">${progress(key)}</div>
      <div class="reading-study-context">${context(key, kind === 'edition-small')}</div>
    </article>`;
    if (direction === 'edition') {
      return `<div class="edition-leads">${list.slice(0, 2).map((key, i) => item(key, i, 'edition-large')).join('')}</div>
        <div class="reading-study-heading"><h2>Still in rotation.</h2><span>${list.length - 2} reads</span></div>
        <div class="edition-rest">${list.slice(2).map((key, i) => item(key, i + 2, 'edition-small')).join('')}</div>`;
    }
    if (direction === 'contact') {
      return `<div class="contact-sheet">${list.map((key, i) => item(key, i, 'contact-plate')).join('')}</div>`;
    }
    return `<div class="reading-ledger">${list.map((key, i) => item(key, i, 'index-line')).join('')}</div>`;
  }
};
