import { describe, it, expect } from 'vitest';
import { RainField, MATRIX_CHARACTERS, rainFontSize } from './matrix-rain/field';
function random(seed = 1) { return () => { seed = (seed * 1664525 + 1013904223) >>> 0; return seed / 4294967296; }; }
describe('reusable matrix rain simulation', () => {
  it('uses the original katakana and numeral alphabet', () => {
    expect(MATRIX_CHARACTERS).toBe('ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ0123456789');
    const field = new RainField(random()); field.resize(1920, 1080, 20);
    for (const stream of field.streams) for (const glyph of stream.glyphs) expect(field.characters[glyph.index]).toMatch(/[ｱ-ﾝ0-9]/);
  });
  it('fills arbitrary widths and adapts column counts to font size', () => {
    const field = new RainField(random());
    for (const width of [320, 900, 2560, 5120]) {
      field.resize(width, 900, 20);
      expect(field.streams.length * field.cellWidth).toBeGreaterThanOrEqual(width);
      expect((field.streams.length - 1) * field.cellWidth).toBeLessThan(width);
    }
    field.resize(900, 900, 20); const columns = field.streams.length;
    field.resize(900, 900, 40); expect(field.streams.length).toBe(Math.ceil(columns / 2));
    field.resize(0, 0, 20); expect(field.streams).toEqual([]);
  });
  it('preserves the ongoing rain when viewport dimensions change', () => {
    const field = new RainField(random()); field.resize(900, 700, 20); field.step(.1);
    const heads = field.streams.map(stream => stream.head);
    field.resize(1200, 900, 20);
    expect(field.streams.slice(0, heads.length).map(stream => stream.head)).toEqual(heads);
    field.resize(320, 640, 20);
    expect(field.streams.map(stream => stream.head)).toEqual(heads.slice(0, field.streams.length));
  });
  it('moves by elapsed time instead of refresh rate', () => {
    const first = new RainField(random()), second = new RainField(random());
    for (const field of [first, second]) { field.resize(20, 1000, 20); field.streams[0].head = 5; }
    first.step(.1); second.step(.05); second.step(.05);
    expect(first.streams[0].head).toBeCloseTo(second.streams[0].head, 10);
    expect(first.streams[0].speed).toBeCloseTo(second.streams[0].speed, 10);
  });
  it('varies lanes, mutates glyphs and recycles completed streams with a pause', () => {
    const field = new RainField(random()); field.resize(900, 600, 20);
    expect(new Set(field.streams.map(stream => stream.speed)).size).toBeGreaterThan(10);
    expect(new Set(field.streams.map(stream => stream.glyphs.length)).size).toBeGreaterThan(3);
    const stream = field.streams[0], before = stream.glyphs.map(glyph => glyph.index);
    for (const glyph of stream.glyphs) glyph.changeIn = 0;
    field.step(.1); expect(stream.glyphs.map(glyph => glyph.index)).not.toEqual(before);
    stream.head = field.rows + stream.glyphs.length + 1;
    field.step(.1);
    expect(field.streams[0]).not.toBe(stream); expect(field.streams[0].head).toBe(-1);
    expect(field.streams[0].delay).toBeGreaterThan(0);
  });
  it('bounds sizes and does not fast-forward after tab suspension', () => {
    expect(rainFontSize(NaN)).toBe(20); expect(rainFontSize(-10)).toBe(8); expect(rainFontSize(1000)).toBe(64);
    const field = new RainField(random()); field.resize(20, 1000, 20);
    const before = field.streams[0].head;
    field.step(3600); expect(field.streams[0].head - before).toBeLessThan(3);
    const after = field.streams[0].head; field.step(NaN); field.step(-1);
    expect(field.streams[0].head).toBe(after);
  });
});
