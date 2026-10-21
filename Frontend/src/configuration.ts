import { identifyConfig, configurationPayload, type Config, type Snapshot } from './model';

type Request = <T>(path: string, method?: string, body?: unknown) => Promise<T>;
export class RequestError extends Error {
  constructor(message: string, readonly status: number) { super(message); }
}

/** Keep reads and writes ordered; only small explicit mutations may retry a stale revision. */
export class ConfigurationClient {
  private current?: Snapshot;
  private pending = Promise.resolve();
  constructor(private request: Request, private changed: (snapshot: Snapshot) => void) {}
  private ordered<T>(operation: () => Promise<T>): Promise<T> {
    const next = this.pending.then(operation);
    this.pending = next.then(() => {}, () => {});
    return next;
  }
  private accept(snapshot: Snapshot): Snapshot {
    snapshot = { ...snapshot, config: identifyConfig(snapshot.config) };
    this.current = snapshot; this.changed(snapshot); return snapshot;
  }
  load(): Promise<Snapshot> {
    return this.ordered(async () => this.accept(await this.request<Snapshot>('/api/config')));
  }
  replace(config: Config, revision: string): Promise<Snapshot> {
    return this.ordered(async () => this.accept(await this.request<Snapshot>('/api/config', 'PUT', { config: configurationPayload(config), revision })));
  }
  update(edit: (config: Config) => void): Promise<Snapshot> {
    return this.ordered(async () => {
      for (let attempt = 0; ; attempt++) {
        const snapshot = this.current ?? this.accept(await this.request<Snapshot>('/api/config'));
        const config = structuredClone(snapshot.config); edit(config);
        try { return this.accept(await this.request<Snapshot>('/api/config', 'PUT', { config: configurationPayload(config), revision: snapshot.revision })); }
        catch (error) {
          if (!(error instanceof RequestError) || error.status !== 409 || attempt > 0) throw error;
          this.accept(await this.request<Snapshot>('/api/config'));
        }
      }
    });
  }
}
