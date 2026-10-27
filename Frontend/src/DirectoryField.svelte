<script lang="ts">
  import DirectoryPicker from './DirectoryPicker.svelte';
  import Icon from './Icon.svelte';
  let { value = $bindable(''), label, host, request, required = false, placeholder = '' }: { value?: string; label: string; host: string; request: <T>(path: string) => Promise<T>; required?: boolean; placeholder?: string } = $props();
  let picking = $state(false);
</script>
<div class="directory-field"><label>{label}<input {required} {placeholder} bind:value /></label><button type="button" aria-label={`Browse ${label}`} title="Select host directory" disabled={!host} onclick={() => picking = true}><Icon name="folder" /></button></div>
{#if picking}<DirectoryPicker {host} initial={value} {request} choose={path => { value = path; picking = false; }} close={() => picking = false} />{/if}
