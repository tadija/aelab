<script lang="ts">
  import Logo from './Logo.svelte';
  import Icon from './Icon.svelte';
  let { password = $bindable(''), error = '', busy = false, focus = false, color, submit, changePassword, screensaver }: {
    password?: string; error?: string; busy?: boolean; focus?: boolean; color?: string; submit: (event: SubmitEvent) => void;
    screensaver?: () => void;
    changePassword: (current: string, replacement: string) => Promise<void>;
  } = $props();
  const supportsMask = CSS.supports('-webkit-text-security', 'disc');
  let input = $state<HTMLInputElement>();
  let changing = $state(false); let saving = $state(false); let replacement = $state(''); let confirmation = $state(''); let message = $state('');
  $effect(() => {
    if (!focus || busy || saving || !input) return;
    const field = input;
    const frame = requestAnimationFrame(() => field.focus({ preventScroll: true }));
    const refocus = () => {
      if (!document.hidden && (document.activeElement === document.body || document.activeElement === field)) {
        field.focus({ preventScroll: true });
      }
    };
    window.addEventListener('focus', refocus);
    document.addEventListener('visibilitychange', refocus);
    return () => {
      cancelAnimationFrame(frame);
      window.removeEventListener('focus', refocus);
      document.removeEventListener('visibilitychange', refocus);
    };
  });
  async function save(event: SubmitEvent) {
    if (!changing) { submit(event); return; }
    event.preventDefault(); if (saving) return;
    message = '';
    if (replacement !== confirmation) { message = 'New passwords do not match'; return; }
    if (new TextEncoder().encode(replacement).length > 1024) { message = 'Use at most 1024 bytes'; return; }
    saving = true;
    try { await changePassword(password, replacement); changing = false; password = ''; replacement = ''; confirmation = ''; message = 'Password changed. Sign in with your new password.'; }
    catch (e) { message = String(e); }
    finally { saving = false; }
  }
  function toggle() { changing = !changing; replacement = ''; confirmation = ''; message = ''; input?.focus(); }
</script>
<div class="login-heading"><div class="brand">{#if screensaver}<button type="button" class="tint-trigger" title="Screensaver" aria-label="Screensaver" onclick={screensaver}><Logo {color} /></button>{:else}<span class="tint-trigger" aria-hidden="true"><Logo {color} /></span>{/if}<h1>aelab</h1></div><span class="muted login-tagline">your lab, connected</span></div>
<form class="login-form" autocomplete="off" onsubmit={save}>
  <input bind:this={input} type={changing || !supportsMask ? 'password' : 'text'} class:masked-password={!changing && supportsMask} aria-label="Administrator password" autocapitalize="none" autocorrect="off" spellcheck={false} oncopy={event => { if (!changing) event.preventDefault(); }} oncut={event => { if (!changing) event.preventDefault(); }} placeholder={changing ? 'Current password' : 'Password'} autocomplete={changing ? 'current-password' : 'off'} required bind:value={password} disabled={busy || saving} />
  <button type="button" class="icon-button" title={changing ? 'Cancel password change' : 'Change password'} aria-label={changing ? 'Cancel password change' : 'Change password'} aria-pressed={changing} onclick={toggle} disabled={busy || saving}><Icon name="key" /></button>
  <button disabled={busy || saving}>{saving ? 'Saving…' : changing ? 'Save' : busy ? 'Signing in…' : 'Sign in'}</button>
  {#if changing}
    <input class="new-password" type="password" aria-label="New password" placeholder="New password (12+ characters)" autocomplete="new-password" minlength="12" required bind:value={replacement} disabled={saving} />
    <input class="new-password" type="password" aria-label="Confirm new password" placeholder="Confirm new password" autocomplete="new-password" minlength="12" required bind:value={confirmation} disabled={saving} />
    <p class="muted password-note">Changing your password invalidates existing logins and pins.</p>
  {/if}
</form>
{#if message || error}<p class="error" role="alert">{message || error}</p>{/if}
<style>
  .masked-password { -webkit-text-security: disc; }
  .login-form { flex-wrap: wrap; }
  .new-password { flex-basis: 100%; }
  .password-note { flex-basis: 100%; margin: 0; font-size: .85rem; }
</style>
