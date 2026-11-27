// The layouts as small pictures: the website's layout cards (docs) and the
// home page draw them from here. The same shapes as the bar's pictures in
// the app (Sources/KachelCore/LayoutIcon.swift).

// Each layout with four windows, in a 120 × 75 box: x, y, width, height as
// fractions. The first window is the master (or the focused one); widescreen-tall
// shows two masters.
export const LAYOUTS = {
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

/** One line about each, for the home page. */
export const BLURBS = {
  tall: 'master and a stack', 'tall-right': 'master on the right', wide: 'master on top',
  'widescreen-tall': 'masters side by side', 'three-column': 'master in the middle',
  'two-pane': 'the rest wait behind', column: 'side by side', rows: 'on top of each other',
  bsp: 'halves, alternating', full: 'one at a time', floating: 'not tiled at all',
};

/** The windows of layout `name` in a W × H box, back to front:
 *  { W, H, shapes: [{ x, y, w, h, role: 'master' | 'window' | 'behind' }] }. */
export function layoutShapes(name) {
  const cells = LAYOUTS[name];
  if (!cells) return null;
  const W = 120, H = 75, pad = 4, gap = 3;
  const box = ([x, y, w, h]) => ({
    x: pad + x * (W - 2 * pad) + gap / 2, y: pad + y * (H - 2 * pad) + gap / 2,
    w: w * (W - 2 * pad) - gap, h: h * (H - 2 * pad) - gap,
  });
  const shapes = [];
  // Windows waiting behind the last placed one peek out above it.
  const placed = cells.filter((c) => c !== 'behind').map(box);
  const behind = cells.filter((c) => c === 'behind').length;
  const front = placed[placed.length - 1];
  for (let i = behind; i > 0; i--) {
    const d = 4 * i;
    shapes.push({ x: front.x + d, y: front.y - d, w: front.w - 2 * d, h: front.h, role: 'behind' });
  }
  const masters = name === 'widescreen-tall' ? 2 : 1;
  placed.forEach((b, i) => shapes.push({ ...b, role: i < masters ? 'master' : 'window' }));
  // The floating ones overlap: the master goes on top.
  if (name === 'floating') shapes.push(shapes.shift());
  return { W, H, shapes };
}
