<script lang="ts">
  import { tick } from 'svelte';
  import { jsonFolds, jsonLines, codeTokens, codeLines } from './json';
  let { value = $bindable(''), disabled = false, language = 'json', wrap = false, label = 'Main configuration JSON' }: { value?: string; disabled?: boolean; language?: string; wrap?: boolean; label?: string } = $props();
  let backdrop = $state<HTMLPreElement>(); let gutter = $state<HTMLDivElement>(); let input = $state<HTMLTextAreaElement>();
  let lineHeights = $state<number[]>([]);
  const highlighted = $derived(codeLines(value, language));
  let collapsed = $state<number[]>([]);
  const ranges = $derived(language === 'json' ? jsonFolds(value) : []);
  const ends = $derived(new Map(ranges.map(range => [range.start, range.end])));
  const rows = $derived(jsonLines(value, ranges, collapsed));
  $effect(() => { void value; collapsed = []; });
  async function measure() {
    await tick();
    if (!backdrop || !input) return;
    backdrop.style.width = `${input.clientWidth}px`;
    lineHeights = Array.from(backdrop.querySelectorAll('.editor-line'), line => line.getBoundingClientRect().height);
    backdrop.scrollTop = input.scrollTop; backdrop.scrollLeft = input.scrollLeft;
    if (gutter) gutter.scrollTop = input.scrollTop;
  }
  $effect(() => { void value; void wrap; void language; void measure(); });
  $effect(() => {
    if (!input) return;
    const observer = new ResizeObserver(() => { void measure(); }); observer.observe(input);
    return () => observer.disconnect();
  });
  function toggle(line: number) { collapsed = collapsed.includes(line) ? collapsed.filter(item => item !== line) : [...collapsed, line]; }
  async function edit() { collapsed = []; await tick(); input?.focus(); }
</script>
{#snippet foldButton(line: number)}
  {#if ends.has(line)}<button type="button" class="fold-toggle" aria-label={`${collapsed.includes(line) ? 'Expand' : 'Fold'} lines ${line + 1}–${ends.get(line)! + 1}`} aria-expanded={!collapsed.includes(line)} {disabled} onclick={() => toggle(line)}>{collapsed.includes(line) ? '▸' : '▾'}</button>{:else}<span class="fold-spacer"></span>{/if}
{/snippet}
<div class="json-editor" class:wrapping={wrap}>
  {#if collapsed.length}
    <div class="folded-preview" role="region" aria-label="Folded configuration preview">
      {#each rows as row}<div class="json-code-line"><div class="folded-number"><span>{row.number + 1}</span>{@render foldButton(row.number)}</div><code>{#each codeTokens(row.text, language) as token}<span class={token.kind}>{token.text}</span>{/each}</code></div>{/each}
    </div>
  {:else}
    <div class="json-gutter" bind:this={gutter}>{#each rows as row}<div style:height={`${lineHeights[row.number] ?? 20.15}px`}><span>{row.number + 1}</span>{@render foldButton(row.number)}</div>{/each}</div>
    <pre bind:this={backdrop} aria-hidden="true">{#each highlighted as line}<span class="editor-line">{#each line as token}<span class={token.kind}>{token.text}</span>{/each}</span>{/each}</pre>
    <textarea wrap={wrap ? 'soft' : 'off'} bind:this={input} aria-label={label} spellcheck="false" autocapitalize="off" autocomplete="off" bind:value {disabled} onscroll={event => { if (backdrop && gutter) { backdrop.scrollTop = gutter.scrollTop = event.currentTarget.scrollTop; backdrop.scrollLeft = event.currentTarget.scrollLeft; } }}></textarea>
  {/if}
</div>
{#if collapsed.length}<div class="fold-notice"><small>Folded preview · source text is unchanged.</small><button type="button" onclick={edit} {disabled}>Expand all to edit</button></div>{/if}
