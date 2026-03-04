import { useState, useEffect } from 'react';
import { listMyWebsites } from '../lib/websites';
import type { WebsiteAssignment, Website } from '../lib/types';

type AssignmentWithWebsite = WebsiteAssignment & { website?: Website & { branch?: { name: string } } };

export default function MyWebsites() {
  const [items, setItems] = useState<AssignmentWithWebsite[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    listMyWebsites().then((data) => {
      setItems(data as AssignmentWithWebsite[]);
      setLoading(false);
    });
  }, []);

  const copyAlias = (alias: string) => {
    navigator.clipboard.writeText(alias);
    // Optional: show toast; for now just copy
  };

  const hasPrimary = items.some((a) => a.is_primary);

  if (loading) {
    return (
      <div>
        <p className="text-gray-400">กำลังโหลด...</p>
      </div>
    );
  }

  return (
    <div>
      <h1 className="text-premium-gold text-xl font-semibold mb-4">เว็บที่ฉันดูแล</h1>

      {!hasPrimary && items.length > 0 && (
        <div className="mb-4 p-4 rounded-lg border border-premium-gold/40 bg-premium-gold/10 text-premium-gold">
          ยังไม่ได้ตั้งเว็บหลัก กรุณาให้ผู้ดูแลระบบกำหนด
        </div>
      )}

      {items.length === 0 ? (
        <p className="text-gray-400">ยังไม่มีเว็บที่คุณดูแล</p>
      ) : (
        <div className="grid gap-4 sm:grid-cols-1 md:grid-cols-2 lg:grid-cols-3">
          {items.map((a) => {
            const w = a.website;
            return (
              <div
                key={a.id}
                className="border border-premium-gold/20 rounded-lg p-4 bg-premium-darker/80 hover:border-premium-gold/40 transition"
              >
                <div className="flex items-start justify-between gap-2">
                  <div className="min-w-0 flex-1">
                    <h3 className="font-medium text-gray-200 truncate">{w?.name ?? '-'}</h3>
                    <div className="mt-2 flex items-center gap-2 flex-wrap">
                      <span className="font-mono text-premium-gold text-sm">{w?.alias ?? '-'}</span>
                      <button
                        type="button"
                        onClick={() => w?.alias && copyAlias(w.alias)}
                        className="text-gray-400 hover:text-premium-gold text-sm"
                        title="คัดลอก alias"
                      >
                        คัดลอก
                      </button>
                    </div>
                  </div>
                  {a.is_primary && (
                    <span className="shrink-0 px-2 py-0.5 rounded text-xs font-medium bg-premium-gold/25 text-premium-gold border border-premium-gold/40">
                      เว็บหลัก
                    </span>
                  )}
                </div>
                {w?.url && (
                  <a
                    href={w.url}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="mt-3 inline-block text-sm text-premium-gold hover:underline truncate max-w-full"
                  >
                    เปิดเว็บ
                  </a>
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
