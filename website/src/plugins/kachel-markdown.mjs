// A Sätteri hast plugin: small touches on the Markdown in ../docs, so the pages stay plain Markdown
// (readable on GitHub too) and the website draws them nicer:
//
// - Shortcuts in inline code (`mod-shift-1…9`) become keycaps.
// - The layouts table (first column "Layout") becomes a gallery of cards,
//   each with a little picture of the layout.

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

// Each layout with four windows, in a 120 × 75 box: x, y, width, height as
// fractions. The first window is the master (or the focused one); widescreen-tall
// shows two masters.
const LAYOUTS = {
  tall: [[0, 0, .5, 1], [.5, 0, .5, 1 / 3], [.5, 1 / 3, .5, 1 / 3], [.5, 2 / 3, .5, 1 / 3]],
  'tall-right': [[.5, 0, .5, 1], [0, 0, .5, 1 / 3], [0, 1 / 3, .5, 1 / 3], [0, 2 / 3, .5, 1 / 3]],
  wide: [[0, 0, 1, .5], [0, .5, 1 / 3, .5], [1 / 3, .5, 1 / 3, .5], [2 / 3, .5, 1 / 3, .5]],
  'widescreen-tall': [[0, 0, .3, 1], [.3, 0, .3, 1], [.6, 0, .4, .5], [.6, .5, .4, .5]],
  'three-column': [[.25, 0, .5, 1], [.75, 0, .25, .5], [.75, .5, .25, .5], [0, 0, .25, 1]],
  'two-pane': [[0, 0, .5, 1], [.5, 0, .5, 1], 'behind', 'behind'],
  column: [[0, 0, .25, 1], [.25, 0, .25, 1], [.5, 0, .25, 1], [.75, 0, .25, 1]],
  rows: [[0, 0, 1, .25], [0, .25, 1, .25], [0, .5, 1, .25], [0, .75, 1, .25]],
  bsp: [[0, 0, .5, 1], [.5, 0, .5, .5], [.5, .5, .25, .5], [.75, .5, .25, .5]],
  full: [[0, 0, 1, 1], 'behind', 'behind'],
  floating: [[.06, .1, .5, .55], [.42, .3, .5, .6], [.2, .5, .35, .42]],
};

function picture(name) {
  const cells = LAYOUTS[name];
  if (!cells) return null;
  const W = 120, H = 75, pad = 4, gap = 3;
  const box = ([x, y, w, h]) => ({
    x: pad + x * (W - 2 * pad) + gap / 2, y: pad + y * (H - 2 * pad) + gap / 2,
    w: w * (W - 2 * pad) - gap, h: h * (H - 2 * pad) - gap,
  });
  const rect = (b, cls) => el('rect', { x: b.x, y: b.y, width: b.w, height: b.h, rx: 3.5, className: [cls] });
  const shapes = [];
  // Windows waiting behind the last placed one peek out above it.
  const placed = cells.filter((c) => c !== 'behind').map(box);
  const behind = cells.filter((c) => c === 'behind').length;
  const front = placed[placed.length - 1];
  for (let i = behind; i > 0; i--) {
    const d = 3 * i;
    shapes.push(rect({ x: front.x + d, y: front.y - d, w: front.w - 2 * d, h: front.h }, 'behind'));
  }
  const masters = name === 'widescreen-tall' ? 2 : 1;
  placed.forEach((b, i) => shapes.push(rect(b, i < masters ? 'master' : 'window')));
  // The floating ones overlap: the master goes on top.
  if (name === 'floating') shapes.push(shapes.shift());
  return el('svg', { viewBox: `0 0 ${W} ${H}`, className: ['layout-picture'], ariaHidden: 'true' }, [
    el('rect', { x: 0.5, y: 0.5, width: W - 1, height: H - 1, rx: 7, className: ['screen'] }),
    ...shapes,
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
