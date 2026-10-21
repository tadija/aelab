<script lang="ts">
  import type { Snippet } from 'svelte';
  let { title, expanded = true, onToggle, actions, children }: { title: string; expanded?: boolean; onToggle?: (value: boolean) => void; actions?: Snippet; children: Snippet } = $props();
</script>
<section aria-label={title}>
  <h2><button class="section-toggle" aria-label={title} aria-expanded={expanded} onclick={() => onToggle?.(!expanded)}><span aria-hidden="true">{expanded ? '▾' : '▸'}</span>{title}</button>{#if actions}{@render actions()}{/if}</h2>
  {#if expanded}{@render children()}{/if}
</section>
