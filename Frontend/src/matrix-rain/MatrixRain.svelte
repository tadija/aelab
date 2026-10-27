<script lang="ts">
  import { onMount } from 'svelte';
  import { createMatrixRain } from './renderer';
  import { DEFAULT_FONT_SIZE } from './field';
  let { foreground = '#22c55e', background = '#000000', fontSize = DEFAULT_FONT_SIZE }: {
    foreground?: string; background?: string; fontSize?: number;
  } = $props();
  let canvas: HTMLCanvasElement;
  let rain: ReturnType<typeof createMatrixRain> | undefined;
  onMount(() => {
    rain = createMatrixRain(canvas, { foreground, background, fontSize });
    return () => rain?.destroy();
  });
  $effect(() => { const options = { foreground, background, fontSize }; rain?.update(options); });
</script>
<canvas bind:this={canvas} aria-hidden="true"></canvas>
<style>
  canvas { display: block; width: 100%; height: 100%; }
</style>
