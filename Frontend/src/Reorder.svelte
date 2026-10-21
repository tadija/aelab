<script lang="ts">
  import { onMount } from 'svelte';
  import Icon from './Icon.svelte';
  import { rowDragType } from './rowOrder';
  let { id, name, group, rows, move, disabled = false }: { id: string; name: string; group: string; rows: { id: string }[]; move: (id: string, target: string) => void; disabled?: boolean } = $props();
  let menu: HTMLDetailsElement; let open = $state(false);
  const index = $derived(rows.findIndex(row => row.id === id));
  function step(direction: number) {
    const target = rows[index + direction];
    if (!disabled && target) { open = false; move(id, target.id); }
  }
  function drag(event: DragEvent) {
    if (disabled) { event.preventDefault(); return; }
    open = false;
    event.dataTransfer!.setData(rowDragType, JSON.stringify({ group, id }));
    event.dataTransfer!.effectAllowed = 'move';
  }
  onMount(() => {
    const dismiss = (event: PointerEvent) => { if (event.target instanceof Node && !menu.contains(event.target)) open = false; };
    document.addEventListener('pointerdown', dismiss);
    return () => document.removeEventListener('pointerdown', dismiss);
  });
</script>
<details class="reorder-control" bind:this={menu} bind:open>
  <summary draggable={!disabled} aria-label={`Reorder ${name}`} aria-disabled={disabled} title="Drag to reorder, or use arrow keys / move controls" ondragstart={drag} onkeydown={event => { if (event.key === 'ArrowUp' || event.key === 'ArrowDown') { event.preventDefault(); step(event.key === 'ArrowUp' ? -1 : 1); } if (event.key === 'Escape') open = false; }}><Icon name="grip" /></summary>
  <div class="reorder-menu"><button disabled={disabled || index <= 0} aria-label={`Move ${name} up`} onclick={() => step(-1)}>↑ Move up</button><button disabled={disabled || index >= rows.length - 1} aria-label={`Move ${name} down`} onclick={() => step(1)}>↓ Move down</button></div>
</details>
