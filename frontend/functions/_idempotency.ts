/**
 * Optional idempotency via Durable Object (OKACE_IDEMPOTENCY).
 * If binding is not set, callers use in-memory fallback.
 */

const DO_PATH_CHECK = '/checkOrReserve';
const DO_PATH_STORE = '/store';

async function sha256Hex(s: string): Promise<string> {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

async function doNameFromKey(key: string): Promise<string> {
  const hex = await sha256Hex(key);
  return 'idem-' + hex.slice(0, 32);
}

export type IdempotencyBinding = DurableObjectNamespace;

export async function idempotencyCheckOrReserve(
  binding: IdempotencyBinding,
  key: string
): Promise<{ hit: true; status: number; body: string } | { run: true }> {
  const name = await doNameFromKey(key);
  const id = binding.idFromName(name);
  const stub = binding.get(id);
  const res = await stub.fetch('https://do/internal' + DO_PATH_CHECK, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ key }),
  });
  if (!res.ok) return { run: true };
  const data = (await res.json()) as { hit?: boolean; run?: boolean; status?: number; body?: string };
  if (data.hit === true && typeof data.status === 'number' && typeof data.body === 'string') {
    return { hit: true, status: data.status, body: data.body };
  }
  if (data.run === true) return { run: true };
  return { run: true };
}

export async function idempotencyStore(
  binding: IdempotencyBinding,
  key: string,
  status: number,
  responseBody: string
): Promise<void> {
  const name = await doNameFromKey(key);
  const id = binding.idFromName(name);
  const stub = binding.get(id);
  await stub.fetch('https://do/internal' + DO_PATH_STORE, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ key, status, responseBody }),
  });
}
