<script lang="ts">
  let { color, label, class: className = '' }: { color?: string; label?: string; class?: string } = $props();
</script>
<svg class={className} viewBox="0 0 24 24" style:color aria-label={label} role={label ? 'img' : undefined} aria-hidden={label ? undefined : true}><circle cx="12" cy="12" r="8.5" fill="none" stroke="currentColor" stroke-width="3"/><circle cx="12" cy="12" r="3" fill="currentColor"/></svg>

<style>
  svg { width: 24px; height: 24px; flex-shrink: 0; }
</style>
