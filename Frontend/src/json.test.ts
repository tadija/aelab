import { expect, it } from 'vitest';
import { jsonFolds, jsonLines, jsonTokens } from './json';
it('folds multiline containers while ignoring braces and escaped quotes inside strings', () => {
 const source = '{\n  "items": [\n    "brace } and \\\" quote",\n    {"inline": true}\n  ]\n}\n';
 expect(jsonFolds(source)).toEqual([{start:0,end:5},{start:1,end:4}]);
 expect(jsonFolds('{"inline":[]}')).toEqual([]);
});
it('keeps source line numbers and all original text when folds are expanded', () => {
 const source = '{\n  "items": [\n    1\n  ],\n  "other": true\n}\n';
 const ranges = jsonFolds(source);
 expect(jsonLines(source,ranges,[1]).map(row => row.number)).toEqual([0,1,4,5,6]);
 expect(jsonLines(source,ranges,[0])).toHaveLength(2);
 expect(jsonLines(source,ranges,[]).map(row=>row.text).join('\n')).toBe(source);
});
it('disables folding for malformed JSON without changing its contents', () => {
 const source = '{\n "broken": [\n';
 expect(jsonFolds(source)).toEqual([]);
 expect(jsonLines(source,[],[]).map(row=>row.text).join('\n')).toBe(source);
});
it('returns plain text tokens without creating HTML', () => {
 const source = '{"name":"<script>unsafe()</script>","count":42}';
 const tokens = jsonTokens(source);
 expect(tokens.map(token=>token.text).join('')).toBe(source);
 expect(tokens.some(token=>token.kind==='json-string' && token.text.includes('<script>'))).toBe(true);
});
