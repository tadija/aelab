import { expect, it } from 'vitest';
import { codeTokens } from './json';
it('highlights script sources without losing or interpreting their text', () => {
  for (const [language, source] of [['bash', '#!/bin/bash\nif true; then echo "<script>"; fi\n'], ['ruby', '# comment\nputs "hello"\n'], ['swift', 'import Foundation\nlet count = 42 // count\n']]) {
    const tokens = codeTokens(source, language);
    expect(tokens.map(token => token.text).join('')).toBe(source);
    expect(tokens.some(token => token.kind === 'json-literal')).toBe(true);
    expect(tokens.some(token => token.kind === 'code-comment')).toBe(true);
  }
});

import { codeLines } from './json';
it('preserves logical lines and multiline highlighting when wrapping', () => {
  const source = '/* first\nsecond */\nlet value = "long text"\n';
  const lines = codeLines(source, 'swift');
  expect(lines.map(line => line.map(token => token.text).join('')).join('\n')).toBe(source);
  expect(lines).toHaveLength(4); expect(lines[1][0].kind).toBe('code-comment');
});
