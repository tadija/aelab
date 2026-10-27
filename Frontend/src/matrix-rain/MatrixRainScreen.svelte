<script lang="ts">
  import { onMount, type Snippet } from 'svelte';
  import MatrixRain from './MatrixRain.svelte';
  import { DEFAULT_FONT_SIZE, rainFontSize } from './field';
  let { foreground = '#22c55e', background = '#000000', fontSize = $bindable(DEFAULT_FONT_SIZE), onclose, children, label = 'Matrix rain screensaver', actionLabel = 'Exit matrix rain', description = 'Press Escape or click to exit. Use + and - to resize, and 0 to reset.' }: {
    foreground?: string; background?: string; fontSize?: number; onclose: () => void; children?: Snippet; label?: string; actionLabel?: string; description?: string;
  } = $props();
  $effect(() => { const size = rainFontSize(fontSize); if (fontSize !== size) fontSize = size; });
  const helpID = $props.id();
  let dialog: HTMLDialogElement;
  function keydown(event: KeyboardEvent) {
    event.stopPropagation();
    if (event.isComposing || event.ctrlKey || event.metaKey || event.altKey) return;
    if (event.key === 'Escape') { event.preventDefault(); onclose(); return; }
    if (event.key === 'Tab') {
      const items = Array.from(dialog.querySelectorAll<HTMLElement>('button:not(:disabled),input:not(:disabled),select:not(:disabled),textarea:not(:disabled),a[href],[tabindex="0"]')).filter(element => element.getClientRects().length);
      const index = items.indexOf(document.activeElement as HTMLElement);
      if (index < 0 || (event.shiftKey && index === 0) || (!event.shiftKey && index === items.length - 1)) {
        event.preventDefault(); (event.shiftKey ? items.at(-1) : items[0])?.focus();
      }
      return;
    }
    if (event.target instanceof Element && event.target.closest('input,textarea,select,[contenteditable]')) return;
    if (['+', '=', '-', '_', '0'].includes(event.key)) {
      event.preventDefault();
      fontSize = event.key === '0' ? DEFAULT_FONT_SIZE : rainFontSize(fontSize + (event.key === '+' || event.key === '=' ? 2 : -2));
    }
  }
  onMount(() => {
    const previousFocus = document.activeElement;
    const overflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden'; dialog.showModal();
    return () => {
      dialog.close(); document.body.style.overflow = overflow;
      if (previousFocus instanceof HTMLElement && previousFocus.isConnected) previousFocus.focus({ preventScroll: true });
    };
  });
</script>
<dialog bind:this={dialog} aria-label={label} aria-describedby={helpID}
  style:--rain-background={background}
  oncancel={event => { event.preventDefault(); onclose(); }} onkeydown={keydown}>
  <button class="surface" type="button" aria-label={actionLabel} onclick={onclose} autofocus>
    <MatrixRain {foreground} {background} {fontSize} />
  </button>
  {#if children}<div class="content">{@render children()}</div>{/if}
  <span id={helpID} hidden>{description}</span>
</dialog>
<style>
  dialog { position: fixed; inset: 0; width: 100vw; height: 100dvh; max-width: none; max-height: none; margin: 0; padding: 0; border: 0; overflow: hidden; background: var(--rain-background); }
  dialog::backdrop { background: var(--rain-background); }
  .surface { all: unset; display: block; position: absolute; inset: 0; width: 100%; height: 100%; cursor: default; }
  .surface:focus-visible { outline: none; }
  .content { position: absolute; inset: 0; display: grid; place-items: center; overflow: auto; padding: min(24px, 3vw); pointer-events: none; }
  .content > :global(*) { pointer-events: auto; }
</style>
