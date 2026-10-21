import { defineConfig } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';
export default defineConfig({ base: './', plugins: [svelte()], server: { proxy: { '/api': 'http://localhost:2108', '/ws': { target: 'ws://localhost:2108', ws: true } } } });
