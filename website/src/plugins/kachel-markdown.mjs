// A Sätteri hast plugin: small touches on the Markdown in ../docs, so the pages stay plain Markdown
// (readable on GitHub too) and the website draws them nicer:
//
// - Shortcuts in inline code (`mod-shift-1…9`) become keycaps.
// - The layouts table (first column "Layout") becomes a gallery of cards,
//   each with a little picture of the layout.

import { layoutShapes } from '../layout-pictures.mjs';

const KEY = /^(mod|ctrl|alt|cmd|shift)-\S+$/;

const text = (n) => (n.type === 'text' ? n.value : (n.children || []).map(text).join(''));
const el = (tagName, properties = {}, children = []) => ({ type: 'element', tagName, properties, children });

/** `mod-shift-1…9` → <kbd class="keys"><kbd>mod</kbd><kbd>shift</kbd><kbd>1…9</kbd></kbd> */
function keycaps(code) {
  const s = text(code);
  // A trailing "-" is the minus key itself (`mod--`, `mod-shift--`).
  const parts = s.endsWith('--') ? [...s.slice(0, -2).split('-'), '-'] : s.split('-');
  if (parts.some((p) => p === '')) return null;
  return el('kbd', { className: ['keys'], title: s }, parts.map((p) => el('kbd', {}, [{ type: 'text', value: p }])));
}

function picture(name) {
  const p = layoutShapes(name);
  if (!p) return null;
  return el('svg', { viewBox: `0 0 ${p.W} ${p.H}`, className: ['layout-picture'], ariaHidden: 'true' }, [
    el('rect', { x: 0.5, y: 0.5, width: p.W - 1, height: p.H - 1, rx: 7, className: ['screen'] }),
    ...p.shapes.map((b) => el('rect', { x: b.x, y: b.y, width: b.w, height: b.h, rx: 3.5, className: [b.role] })),
  ]);
}

/** A table whose first header is "Layout" → cards. */
function gallery(table) {
  const head = table.children.find((c) => c.tagName === 'thead');
  const body = table.children.find((c) => c.tagName === 'tbody');
  const first = head && text(head).trim().split(/\s+/)[0];
  if (first !== 'Layout' || !body) return null;
  const cards = [];
  for (const row of body.children.filter((c) => c.tagName === 'tr')) {
    const [nameCell, whatCell] = row.children.filter((c) => c.tagName === 'td');
    const name = text(nameCell).trim();
    const pic = picture(name);
    if (!pic) return null;           // not the table we know: leave it alone
    cards.push(el('div', { className: ['layout-card'], id: `layout-${name}` }, [
      pic,
      el('div', { className: ['layout-text'] }, [
        el('code', { className: ['layout-name'] }, [{ type: 'text', value: name }]),
        el('p', {}, whatCell.children),
      ]),
    ]));
  }
  return el('div', { className: ['layout-gallery', 'not-content'] }, cards);
}

/** For Sätteri, Astro's Markdown processor (see astro.config.mjs). */
export default {
  name: 'kachel',
  element: [
    {
      filter: ['table'],
      visit(node, ctx) {
        const g = gallery(node);
        if (g) ctx.replaceNode(node, g);
      },
    },
    {
      filter: ['code'],
      visit(node, ctx) {
        if (!KEY.test(ctx.textContent(node))) return;
        // Not in code blocks, links or headings.
        for (let p = ctx.parent(node); p && p.type === 'element'; p = ctx.parent(p)) {
          if (['pre', 'a', 'h1', 'h2', 'h3', 'h4'].includes(p.tagName)) return;
        }
        const k = keycaps(node);
        if (k) ctx.replaceNode(node, k);
      },
    },
  ],
};
