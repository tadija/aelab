/** Move only the selected item; preserve IDs, hidden entries and every other item's relative order. */
export function moveRow<T extends { id: string }>(rows: T[], id: string, target: string): boolean {
  const from = rows.findIndex(row => row.id === id), to = rows.findIndex(row => row.id === target);
  if (from < 0 || to < 0 || from === to) return false;
  rows.splice(to, 0, rows.splice(from, 1)[0]);
  return true;
}
export const rowDragType = 'application/x-aelab-row';
type Options = { group: string; move: (id: string, target: string) => void };
/** Only matching configured lists accept a drag; links, text and external drops remain native. */
export function sortable(node: HTMLUListElement, initial: Options) {
  let options = initial;
  const target = (event: DragEvent) => event.target instanceof Element ? event.target.closest<HTMLLIElement>('li[data-reorder-id]') : null;
  function over(event: DragEvent) {
    if (event.dataTransfer?.types.includes(rowDragType) && target(event)?.parentElement === node) { event.preventDefault(); event.dataTransfer.dropEffect = 'move'; }
  }
  function drop(event: DragEvent) {
    const row = target(event);
    if (!row || row.parentElement !== node || !event.dataTransfer?.types.includes(rowDragType)) return;
    event.preventDefault();
    try {
      const data = JSON.parse(event.dataTransfer.getData(rowDragType));
      if (data.group === options.group && typeof data.id === 'string') options.move(data.id, row.dataset.reorderId!);
    } catch { /* Ignore unrelated or malformed drag data. */ }
  }
  node.addEventListener('dragover', over); node.addEventListener('drop', drop);
  return { update(value: Options) { options = value; }, destroy() { node.removeEventListener('dragover', over); node.removeEventListener('drop', drop); } };
}
