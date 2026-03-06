/**
 * GET /api/health
 * สำหรับ monitoring / uptime check — คืน 200 ไม่ยิง DB
 */

export const onRequestGet: PagesFunction = async () => {
  return new Response(
    JSON.stringify({ ok: true, ts: new Date().toISOString() }),
    { status: 200, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } }
  );
};
