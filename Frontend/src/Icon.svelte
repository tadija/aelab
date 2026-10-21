<script lang="ts">
  let { name }: { name: 'rows' | 'grid' | 'code' | 'settings' | 'logout' | 'close' | 'reload' | 'validate' | 'save' | 'edit' | 'filter' | 'chevron' | 'wrap' | 'grip' | 'folder' | 'upload' } = $props();
  const paths = {
    rows: 'M3 3h18v7H3zM3 14h18v7H3z',
    grid: 'M3 3h7v7H3zM14 3h7v7h-7zM3 14h7v7H3zM14 14h7v7h-7z',
    folder: 'M3 7V4h7l2 3h9v13H3V7z',
    upload: 'M12 16V3m-5 5 5-5 5 5M3 15v6h18v-6',
    grip: 'M8 5h.01M16 5h.01M8 12h.01M16 12h.01M8 19h.01M16 19h.01',
    code: 'm8 5-7 7 7 7M16 5l7 7-7 7',
    wrap: 'M3 6h18M3 12h13a4 4 0 0 1 0 8h-4m3-3-3 3 3 3M3 18h4',
    filter: 'M4 5h16M7 12h10M10 19h4', chevron: 'm6 9 6 6 6-6',
    settings: 'M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8M9 3h6l1 3 3 1 2 5-2 5-3 1-1 3H9l-1-3-3-1-2-5 2-5 3-1z',
    logout: 'M10 4H4v16h6M14 8l4 4-4 4M8 12h12',
    close: 'M6 6l12 12M18 6 6 18', reload: 'M20 10a8 8 0 1 0-2 8M20 3v7h-7',
    validate: 'm5 12 4 4L19 6', save: 'M5 3h12l4 4v14H3V3h2m2 0v6h10V3M7 21v-8h10v8',
    edit: 'm4 16-1 5 5-1L21 7l-4-4L4 16m10-10 4 4'
  };
</script>
<svg class="icon" viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d={paths[name]} /></svg>
