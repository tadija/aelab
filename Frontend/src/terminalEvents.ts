import { appPath } from './basePath';

// Invalidate the pin list across tabs; each dashboard fetches its own authorized data.
export function terminalEvents(onChange?: (host: string) => void) {
  let channel: BroadcastChannel | undefined;
  try {
    channel = new BroadcastChannel(`aelab-terminals:${appPath('/')}`);
    channel.onmessage = event => {
      if (typeof event.data?.host === 'string' && event.data.host.length <= 64) onChange?.(event.data.host);
    };
  } catch { /* Focus refresh and lightweight polling cover unavailable cross-tab messaging. */ }
  return { changed: (host: string) => channel?.postMessage({ host }), close: () => channel?.close() };
}
