// Keep input sequences independent of the UI; tmux uses the actual host prefix.
export function keySequence(key: string, shift = false, prefix = '\x02'): string | undefined {
  if (/^ctrl-[a-z]$/.test(key)) return String.fromCharCode(key.charCodeAt(5) - 96);
  const keys: Record<string, string> = {
    'tmux-zoom': prefix + 'z', 'tmux-mouse': prefix + 'm', 'copy-mode': prefix + '[',
    'tmux-window': prefix + 'c', 'tmux-split-horizontal': prefix + '%', 'tmux-split-vertical': prefix + '"',
    enter: '\r', tab: shift ? '\x1b[Z' : '\t', escape: '\x1b', backspace: '\x7f',
    delete: shift ? '\x1b[3;2~' : '\x1b[3~', home: shift ? '\x1b[1;2H' : '\x1b[H',
    end: shift ? '\x1b[1;2F' : '\x1b[F', 'page-up': shift ? '\x1b[5;2~' : '\x1b[5~', 'page-down': shift ? '\x1b[6;2~' : '\x1b[6~',
    up: shift ? '\x1b[1;2A' : '\x1b[A', down: shift ? '\x1b[1;2B' : '\x1b[B',
    left: shift ? '\x1b[1;2D' : '\x1b[D', right: shift ? '\x1b[1;2C' : '\x1b[C'
  };
  return keys[key];
}
