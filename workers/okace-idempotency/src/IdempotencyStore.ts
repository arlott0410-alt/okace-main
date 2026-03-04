/**
 * Durable Object: Idempotency store for admin create-user / create-users.
 * Single-flight per key; TTL 10 min (2xx), 30s (4xx), 5xx not cached.
 */

const DEFAULT_TTL_SECONDS = 600;
const TTL_4XX_SECONDS = 30;

export interface IdempotencyEnv {
  IDEMPOTENCY_TTL_SECONDS?: string;
}

interface StoredEntry {
  status: number;
  body: string;
  createdAt: number;
}

interface InFlight {
  promise: Promise<{ status: number; body: string }>;
  resolve: (v: { status: number; body: string }) => void;
}

export class IdempotencyStore implements DurableObject {
  private ttlSeconds = DEFAULT_TTL_SECONDS;
  private inFlight = new Map<string, InFlight>();

  constructor(private state: DurableObjectState, env: IdempotencyEnv) {
    const ttl = env.IDEMPOTENCY_TTL_SECONDS;
    if (ttl != null && ttl !== '') {
      const n = parseInt(ttl, 10);
      if (Number.isFinite(n) && n > 0) this.ttlSeconds = n;
    }
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;
    if (request.method === 'POST' && path === '/checkOrReserve') {
      return this.handleCheckOrReserve(request);
    }
    if (request.method === 'POST' && path === '/store') {
      return this.handleStore(request);
    }
    return new Response('Not Found', { status: 404 });
  }

  private ttlForStatus(status: number): number {
    if (status >= 500) return 0;
    if (status >= 400) return TTL_4XX_SECONDS;
    return this.ttlSeconds;
  }

  private async handleCheckOrReserve(request: Request): Promise<Response> {
    const body = (await request.json()) as { key: string };
    const key = typeof body?.key === 'string' ? body.key : '';
    if (!key) {
      return new Response(JSON.stringify({ error: 'Missing key' }), { status: 400, headers: { 'Content-Type': 'application/json' } });
    }
    const entry = await this.state.storage.get<StoredEntry>(key);
    const now = Date.now();
    if (entry && entry.createdAt) {
      const ttlMs = this.ttlForStatus(entry.status) * 1000;
      if (ttlMs > 0 && now - entry.createdAt < ttlMs) {
        return new Response(JSON.stringify({ hit: true, status: entry.status, body: entry.body }), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        });
      }
    }
    const existing = this.inFlight.get(key);
    if (existing) {
      const result = await existing.promise;
      return new Response(JSON.stringify({ hit: true, status: result.status, body: result.body }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      });
    }
    let resolve!: (v: { status: number; body: string }) => void;
    const promise = new Promise<{ status: number; body: string }>((r) => {
      resolve = r;
    });
    this.inFlight.set(key, { promise, resolve });
    return new Response(JSON.stringify({ run: true }), { status: 200, headers: { 'Content-Type': 'application/json' } });
  }

  private async handleStore(request: Request): Promise<Response> {
    const body = (await request.json()) as { key: string; status: number; responseBody: string };
    const key = typeof body?.key === 'string' ? body.key : '';
    const status = typeof body?.status === 'number' ? body.status : 500;
    const responseBody = typeof body?.responseBody === 'string' ? body.responseBody : '{}';
    if (!key) {
      return new Response(JSON.stringify({ error: 'Missing key' }), { status: 400, headers: { 'Content-Type': 'application/json' } });
    }
    const waiter = this.inFlight.get(key);
    if (waiter) {
      this.inFlight.delete(key);
      waiter.resolve({ status, body: responseBody });
    }
    const ttl = this.ttlForStatus(status);
    if (ttl > 0) {
      await this.state.storage.put(key, {
        status,
        body: responseBody,
        createdAt: Date.now(),
      });
    }
    return new Response(JSON.stringify({ ok: true }), { status: 200, headers: { 'Content-Type': 'application/json' } });
  }
}
