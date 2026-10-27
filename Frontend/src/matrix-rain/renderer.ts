import { DEFAULT_FONT_SIZE, RainField, rainFontSize } from './field';
export type RainOptions = { foreground?: string; background?: string; fontSize?: number };
const defaults = { foreground: '#22c55e', background: '#000000', fontSize: DEFAULT_FONT_SIZE };
const font = 'ui-monospace, "SFMono-Regular", Menlo, Consolas, "Liberation Mono", monospace';

/** Mount on any sized canvas; the returned controller owns and cleans up all animation work. */
export function createMatrixRain(canvas: HTMLCanvasElement, initial: RainOptions = {}) {
  const context = canvas.getContext('2d', { alpha: false });
  if (!context) return { update(_options: RainOptions) {}, destroy() {} };
  const ctx = context;
  const field = new RainField();
  const atlas = document.createElement('canvas');
  const ink = atlas.getContext('2d')!;
  const probe = document.createElement('canvas'); probe.width = probe.height = 1;
  const color = probe.getContext('2d', { willReadFrequently: true })!;
  let options = { ...defaults, ...initial, fontSize: rainFontSize(initial.fontSize ?? DEFAULT_FONT_SIZE) };
  let width = 0, height = 0, ratio = 1, screenRatio = 0, renderedSize = 0;
  let frame = 0, lastTime = 0, destroyed = false;
  let atlasKey = '';
  let background = defaults.background, tileWidth = 0, tileHeight = 0, padding = 0;

  function buildAtlas(force = false) {
    canvas.style.color = options.foreground; canvas.style.backgroundColor = options.background;
    const style = getComputedStyle(canvas);
    background = style.backgroundColor;
    const key = `${options.fontSize}|${ratio}|${style.color}|${background}`;
    if (!force && key === atlasKey) return;
    atlasKey = key;
    // Resolve any CSS color (including variables) without assuming RGB input syntax.
    color.clearRect(0, 0, 1, 1);
    color.fillStyle = background; color.fillRect(0, 0, 1, 1);
    const back = color.getImageData(0, 0, 1, 1).data;
    color.clearRect(0, 0, 1, 1); color.fillStyle = style.color; color.fillRect(0, 0, 1, 1);
    const front = color.getImageData(0, 0, 1, 1).data;
    const highlight = back[0] * .2126 + back[1] * .7152 + back[2] * .0722 > 140 ? 0 : 255;
    const head = `rgb(${Array.from(front).slice(0, 3).map(value => Math.round(value * .3 + highlight * .7)).join(',')})`;
    // Cache glyphs until the font, palette or backing scale actually changes.
    padding = Math.ceil(options.fontSize * .45);
    tileWidth = field.cellWidth + padding * 2; tileHeight = field.cellHeight + padding * 2;
    atlas.width = Math.ceil(tileWidth * field.characters.length * ratio);
    atlas.height = Math.ceil(tileHeight * 2 * ratio);
    ink.setTransform(ratio, 0, 0, ratio, 0, 0);
    ink.font = `500 ${options.fontSize}px ${font}`; ink.textAlign = 'center'; ink.textBaseline = 'middle';
    for (let index = 0; index < field.characters.length; index++) {
      const x = index * tileWidth + padding + field.cellWidth / 2;
      const y = padding + field.cellHeight / 2;
      ink.fillStyle = style.color; ink.fillText(field.characters[index], x, y);
      ink.fillStyle = head; ink.shadowColor = style.color; ink.shadowBlur = options.fontSize * .35;
      ink.fillText(field.characters[index], x, y + tileHeight); ink.shadowBlur = 0;
    }
  }
  function paint() {
    ctx.globalAlpha = 1; ctx.fillStyle = background; ctx.fillRect(0, 0, width, height);
    for (let column = 0; column < field.streams.length; column++) {
      const stream = field.streams[column];
      if (stream.delay > 0) continue;
      const head = Math.floor(stream.head);
      for (let offset = stream.glyphs.length - 1; offset >= 0; offset--) {
        const row = head - offset, glyph = stream.glyphs[offset];
        if (row < 0 || row >= field.rows || !glyph.visible) continue;
        ctx.globalAlpha = stream.opacity[offset];
        ctx.drawImage(atlas, glyph.index * tileWidth * ratio, offset === 0 ? tileHeight * ratio : 0,
          tileWidth * ratio, tileHeight * ratio, column * field.cellWidth - padding,
          row * field.cellHeight - padding, tileWidth, tileHeight);
      }
    }
    ctx.globalAlpha = 1;
  }
  function resize() {
    if (destroyed) return;
    const bounds = canvas.getBoundingClientRect();
    const nextWidth = Math.max(1, bounds.width), nextHeight = Math.max(1, bounds.height), nextRatio = window.devicePixelRatio || 1;
    if (width === nextWidth && height === nextHeight && screenRatio === nextRatio && renderedSize === options.fontSize) return;
    width = nextWidth; height = nextHeight; screenRatio = nextRatio; renderedSize = options.fontSize;
    // Keep retina text crisp without allocating enormous buffers on large displays.
    ratio = Math.min(screenRatio, 2, Math.sqrt(8_000_000 / (width * height)));
    canvas.width = Math.max(1, Math.round(width * ratio)); canvas.height = Math.max(1, Math.round(height * ratio));
    ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
    field.resize(width, height, options.fontSize); buildAtlas(); paint();
  }
  function animate(time: number) {
    if (destroyed || document.hidden) { frame = 0; return; }
    if (screenRatio !== window.devicePixelRatio) resize();
    if (!lastTime || time - lastTime >= 1000 / 30 - .5) {
      field.step(lastTime ? (time - lastTime) / 1000 : 0); paint(); lastTime = time;
    }
    frame = requestAnimationFrame(animate);
  }
  function visibility() {
    cancelAnimationFrame(frame); frame = 0; lastTime = 0;
    if (!document.hidden && !destroyed) frame = requestAnimationFrame(animate);
  }
  const observer = new ResizeObserver(resize); observer.observe(canvas);
  window.addEventListener('resize', resize);
  document.addEventListener('visibilitychange', visibility);
  resize(); visibility();
  // Rebuild cached glyphs if a host page loads its fonts after mounting the canvas.
  const fontsLoaded = () => { if (!destroyed) { buildAtlas(true); paint(); } };
  document.fonts?.addEventListener('loadingdone', fontsLoaded);
  return {
    update(next: RainOptions) {
      if (destroyed) return;
      const updated = { ...options, ...next, fontSize: rainFontSize(next.fontSize ?? options.fontSize) };
      const changedSize = updated.fontSize !== options.fontSize;
      options = updated;
      if (changedSize) resize(); else { buildAtlas(); paint(); }
    },
    destroy() {
      destroyed = true; cancelAnimationFrame(frame); observer.disconnect();
      window.removeEventListener('resize', resize); document.removeEventListener('visibilitychange', visibility);
      document.fonts?.removeEventListener('loadingdone', fontsLoaded);
      field.streams = [];
      atlas.width = atlas.height = probe.width = probe.height = 0; canvas.width = canvas.height = 0;
    },
  };
}
