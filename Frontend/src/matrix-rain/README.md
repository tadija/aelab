# Matrix rain

A small, standalone Svelte 5 / TypeScript effect. Copy this directory into another project; it has no aelab, server, routing, stylesheet, font-download or package dependencies beyond Svelte. Hummingbird serves it like any other compiled frontend asset.

The exact half-width katakana and numerals come from [the original iOS Matrix Rain](https://github.com/tadija/matrix-rain/blob/master/Matrix%20Rain/Matrix.swift). Streams have independent lengths, speeds, acceleration, pauses and character-change intervals, with fading trails and contrasting heads.

## A background or embedded effect

Give the parent a defined size. The canvas fills that container and stays decorative, leaving interaction to its parent.

```svelte
<script lang="ts">
  import MatrixRain from './matrix-rain/MatrixRain.svelte';
</script>

<div style="height: 100dvh">
  <MatrixRain foreground="#22c55e" background="#000000" fontSize={20} />
</div>
```

| Prop | Default | Meaning |
| --- | --- | --- |
| `foreground` | `#22c55e` | Main glyph color; accepts CSS colors and variables |
| `background` | `#000000` | Background color; use an opaque color |
| `fontSize` | `20` | CSS pixels, clamped to 8–64; browser zoom remains available |

## A manually opened screensaver

The independent wrapper adds a native modal dialog, viewport sizing, focus restoration, scroll locking and keyboard controls. Optional `children` content is centered above the rain. It does not activate itself, authenticate, lock a session or store preferences.

```svelte
<script lang="ts">
  import MatrixRainScreen from './matrix-rain/MatrixRainScreen.svelte';
  let active = $state(false);
  let fontSize = $state(20);
</script>

<button onclick={() => active = true}>Matrix rain</button>
{#if active}
  <MatrixRainScreen foreground="#22c55e" background="#000000"
    bind:fontSize onclose={() => active = false} />
{/if}
```

Only the rain is visible. Escape or a click on the rain exits. Plain `+`/`−` change size; `0` resets it. Ctrl/Cmd shortcuts retain their browser behavior. Shortcut instructions remain available to assistive technology without any visible labels. Background content is inert while the dialog is open.

`onclose` is a dismissal **request**: the parent decides when to unmount the screen. For example, a host app can reveal a sign-in form in `children` and keep the rain mounted until its server authenticates the user. Set `label`, `actionLabel` and `description` to describe that behavior accessibly. Focus stays within the modal, and shortcuts never intercept text inputs. The renderer knows nothing about authentication; aelab’s UI-only password confirmation and shared login form live outside this directory; its sessions and API/WebSocket traffic remain active.

The effect is explicitly started by the user in the screensaver wrapper. For an automatically displayed background, the embedding app should decide when motion is appropriate, including any reduced-motion preference.

## Without Svelte

```ts
import { createMatrixRain } from './matrix-rain/renderer';
// Give the canvas CSS dimensions inside a sized container.
canvas.style.width = '100%'; canvas.style.height = '100%';
const rain = createMatrixRain(canvas, {
  foreground: '#22c55e', background: '#000000', fontSize: 20,
});
rain.update({ fontSize: 24 });
// Required when the canvas is removed:
rain.destroy();
```

The renderer resolves CSS colors when mounted or updated, caches glyphs and trail opacity, preserves streams through viewport resizes, targets 30 fps, responds to container/viewport/pixel-density changes, caps the backing buffer at roughly eight million pixels and pauses when the document is hidden. Destroying it cancels the frame and removes its observers/listeners. The simulation in `field.ts` has no DOM dependency.
