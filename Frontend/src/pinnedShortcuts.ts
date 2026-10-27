export function pinnedShortcutAction(digits: string, numbers: number[]): 'open' | 'wait' | 'ignore' {
  if (numbers.some(number => String(number).startsWith(digits) && String(number).length > digits.length)) return 'wait';
  return numbers.includes(Number(digits)) ? 'open' : 'ignore';
}
