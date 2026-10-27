/** Dismiss only the top modal, including when focus is outside its contents. */
export function escapeDismiss(node: HTMLElement, dismiss: () => void) {
  const keydown = (event: KeyboardEvent) => {
    if (event.key !== 'Escape' || event.defaultPrevented || event.repeat || event.isComposing) return;
    if (Array.from(document.querySelectorAll('[role="dialog"][aria-modal="true"]')).at(-1) !== node) return;
    event.preventDefault();
    dismiss();
  };
  window.addEventListener('keydown', keydown);
  return { destroy() { window.removeEventListener('keydown', keydown); } };
}
