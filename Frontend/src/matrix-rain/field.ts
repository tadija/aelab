// Half-width katakana and Latin numerals from Marko Tadić's original Matrix Rain.
export const MATRIX_CHARACTERS = 'ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ0123456789';
export const DEFAULT_FONT_SIZE = 20;
export const MIN_FONT_SIZE = 8;
export const MAX_FONT_SIZE = 64;
export function rainFontSize(size: number) {
  return Number.isFinite(size) ? Math.max(MIN_FONT_SIZE, Math.min(MAX_FONT_SIZE, size)) : DEFAULT_FONT_SIZE;
}
export type Glyph = { index: number; changeIn: number; visible: boolean };
export type Stream = { head: number; speed: number; acceleration: number; delay: number; opacity: Float32Array; glyphs: Glyph[] };

/** Time-based simulation, independent of the DOM, Svelte, colors and frame rate. */
export class RainField {
  streams: Stream[] = [];
  cellWidth = 0;
  cellHeight = 0;
  rows = 0;
  readonly characters = Array.from(MATRIX_CHARACTERS);
  constructor(private random: () => number = Math.random) {}
  private between(min: number, max: number) { return min + this.random() * (max - min); }
  private randomizeGlyph(glyph: Glyph, head: boolean) {
    glyph.index = Math.floor(this.random() * this.characters.length);
    glyph.changeIn = this.between(.08, head ? .18 : 1.8);
    glyph.visible = head || this.random() > .07;
    return glyph;
  }
  private stream(initial: boolean): Stream {
    const length = Math.floor(this.between(8, Math.max(12, Math.min(44, this.rows * .85))));
    const brightness = this.between(.5, 1);
    return {
      head: initial ? this.between(-length, this.rows + length * .25) : -1,
      speed: this.between(5, 19), acceleration: this.between(.1, 1.2),
      delay: initial ? 0 : this.between(.1, 2),
      opacity: Float32Array.from({ length }, (_, index) => index === 0 ? 1 : brightness * Math.pow(1 - index / length, 1.6)),
      glyphs: Array.from({ length }, (_, index) => this.randomizeGlyph({ index: 0, changeIn: 0, visible: true }, index === 0)),
    };
  }
  resize(width: number, height: number, fontSize: number) {
    const size = rainFontSize(fontSize);
    const sameFont = this.cellWidth === size * .8;
    this.cellWidth = size * .8; this.cellHeight = size * 1.15;
    this.rows = Math.ceil(Math.max(0, height) / this.cellHeight);
    if (!sameFont) this.streams = [];
    const columns = Math.ceil(Math.max(0, width) / this.cellWidth);
    if (columns < this.streams.length) this.streams.length = columns;
    while (this.streams.length < columns) this.streams.push(this.stream(true));
  }
  step(seconds: number) {
    if (!Number.isFinite(seconds) || seconds <= 0) return;
    // A suspended tab should resume gently rather than fast-forwarding its streams.
    const elapsed = Math.min(seconds, .1);
    for (let column = 0; column < this.streams.length; column++) {
      const stream = this.streams[column];
      if (stream.delay > 0) { stream.delay -= elapsed; continue; }
      stream.head += stream.speed * elapsed + stream.acceleration * elapsed * elapsed / 2;
      stream.speed = Math.min(28, stream.speed + stream.acceleration * elapsed);
      if (stream.head - stream.glyphs.length > this.rows) { this.streams[column] = this.stream(false); continue; }
      for (let index = 0; index < stream.glyphs.length; index++) {
        const glyph = stream.glyphs[index]; glyph.changeIn -= elapsed;
        if (glyph.changeIn <= 0) this.randomizeGlyph(glyph, index === 0);
      }
    }
  }
}
