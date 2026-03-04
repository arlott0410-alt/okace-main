/**
 * Lightweight in-memory query cache for Supabase read queries.
 * - TTL per key (default 60s)
 * - Dedupe in-flight requests (same key returns same Promise)
 * - Invalidate on writes (call invalidate(table) or invalidatePrefix(prefix))
 * Do NOT cache data that must be realtime-accurate unless TTL is very short
 * and realtime handlers invalidate the key.
 */

const DEFAULT_TTL_MS = 60_000; // 60 seconds

type CacheEntry<T> = {
  data: T;
  expiresAt: number;
};

const cache = new Map<string, CacheEntry<unknown>>();
const inFlight = new Map<string, Promise<unknown>>();

function now() {
  return Date.now();
}

function getKey(table: string, filters: Record<string, unknown>): string {
  const parts = Object.keys(filters)
    .sort()
    .map((k) => `${k}=${String(filters[k])}`);
  return `${table}:${parts.join('|')}`;
}

/**
 * Get cached data if present and not expired. Returns undefined if miss or expired.
 */
export function get<T>(table: string, filters: Record<string, unknown>): T | undefined {
  const key = getKey(table, filters);
  const entry = cache.get(key) as CacheEntry<T> | undefined;
  if (!entry || now() >= entry.expiresAt) {
    if (entry) cache.delete(key);
    return undefined;
  }
  return entry.data;
}

/**
 * Set cache entry. TTL in ms (default DEFAULT_TTL_MS).
 */
export function set<T>(
  table: string,
  filters: Record<string, unknown>,
  data: T,
  ttlMs: number = DEFAULT_TTL_MS
): void {
  const key = getKey(table, filters);
  cache.set(key, { data, expiresAt: now() + ttlMs });
}

/**
 * Invalidate all entries for a table (e.g. after insert/update/delete).
 * Call this from write paths or realtime handlers.
 */
export function invalidate(table: string): void {
  const prefix = table + ':';
  for (const key of cache.keys()) {
    if (key.startsWith(prefix)) cache.delete(key);
  }
  for (const key of inFlight.keys()) {
    if (key.startsWith(prefix)) inFlight.delete(key);
  }
}

/**
 * Invalidate by key prefix (e.g. "branches" to clear branches:*).
 */
export function invalidatePrefix(prefix: string): void {
  const p = prefix.endsWith(':') ? prefix : prefix + ':';
  for (const key of cache.keys()) {
    if (key.startsWith(p)) cache.delete(key);
  }
  for (const key of inFlight.keys()) {
    if (key.startsWith(p)) inFlight.delete(key);
  }
}

/**
 * Run a query with cache: if cached and fresh, return it; else run fetcher(),
 * dedupe in-flight, then cache and return.
 * ttlMs: cache TTL (default 60s). Use shorter for frequently updated data.
 */
export async function withCache<T>(
  table: string,
  filters: Record<string, unknown>,
  fetcher: () => Promise<T>,
  ttlMs: number = DEFAULT_TTL_MS
): Promise<T> {
  const key = getKey(table, filters);
  const hit = get<T>(table, filters);
  if (hit !== undefined) return hit;

  let promise = inFlight.get(key) as Promise<T> | undefined;
  if (!promise) {
    promise = Promise.resolve(fetcher()).then((data) => {
      set(table, filters, data, ttlMs);
      inFlight.delete(key);
      return data;
    });
    inFlight.set(key, promise);
  }
  return promise;
}
