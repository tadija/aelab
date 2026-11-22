export type FoldRange = { start: number; end: number };
export type JsonLine = { number: number; text: string; folded: boolean };

/** Zero-based source line ranges. Never fold invalid JSON or braces inside strings. */
export function jsonFolds(value: string): FoldRange[] {
  try { JSON.parse(value); } catch { return []; }
  const stack: number[] = []; const ranges: FoldRange[] = [];
  let line = 0, quoted = false, escaped = false;
  for (const char of value) {
    if (quoted) {
      if (escaped) escaped = false;
      else if (char === '\\') escaped = true;
      else if (char === '"') quoted = false;
    } else if (char === '"') quoted = true;
    else if (char === '{' || char === '[') stack.push(line);
    else if (char === '}' || char === ']') {
      const start = stack.pop();
      if (start !== undefined && line > start) {
        const existing = ranges.find(range => range.start === start);
        if (existing) existing.end = Math.max(existing.end, line); else ranges.push({ start, end: line });
      }
    }
    if (char === '\n') line++;
  }
  return ranges.sort((a, b) => a.start - b.start);
}
export function jsonLines(value: string, ranges: FoldRange[], collapsed: number[]): JsonLine[] {
  const lines = value.split('\n'); const ends = new Map(ranges.map(range => [range.start, range.end]));
  const folded = new Set(collapsed); const result: JsonLine[] = [];
  for (let index = 0; index < lines.length; index++) {
    const end = ends.get(index);
    if (folded.has(index) && end !== undefined) {
      result.push({ number: index, text: `${lines[index]} … ${lines[end].trimStart()}`, folded: true }); index = end;
    } else result.push({ number: index, text: lines[index], folded: false });
  }
  return result;
}
export function jsonTokens(value: string): { text: string; kind: string }[] {
  return value.split(/("(?:[^"\\]|\\.)*"\s*:|"(?:[^"\\]|\\.)*"|\b(?:true|false|null)\b|-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b)/g).map(text => ({ text, kind: /^"/.test(text) ? (/:$/.test(text) ? 'json-key' : 'json-string') : /^(true|false|null)$/.test(text) ? 'json-literal' : /^-?\d/.test(text) ? 'json-number' : '' }));
}
