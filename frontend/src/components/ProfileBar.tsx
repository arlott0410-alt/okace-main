import { Link } from 'react-router-dom';
import type { Profile } from '../lib/types';

/** แถบโปรไฟล์บน Dashboard — ไม่มีขยาย/พับ; ปุ่มขวาไปหน้า บัญชีของฉัน */
export default function ProfileBar({ profile }: { profile: Profile | null }) {
  const displayName = profile?.display_name || profile?.email || 'คุณ';
  const shift = profile?.shift;
  const shiftLabel = shift
    ? `${shift.name}${shift.start_time && shift.end_time ? ` ${shift.start_time.slice(0, 5)}-${shift.end_time.slice(0, 5)}` : ''}`
    : null;
  const avatarUrl = profile?.avatar_url?.trim();
  const initial = (displayName || '?').charAt(0).toUpperCase();

  return (
    <section className="flex items-center gap-8 p-8 rounded-[14px] border border-premium-gold/20 bg-premium-darker/60">
      <div className="shrink-0 w-24 h-24 rounded-full border-2 border-premium-gold/40 overflow-hidden bg-premium-dark flex items-center justify-center">
        {avatarUrl ? (
          <img src={avatarUrl} alt="" className="w-full h-full object-cover" />
        ) : (
          <span className="text-premium-gold font-semibold text-3xl">{initial}</span>
        )}
      </div>
      <div className="flex-1 min-w-0">
        <p className="text-lg text-gray-200">
          สวัสดี, <span className="text-premium-gold font-medium">({displayName})</span>
        </p>
        {shiftLabel && (
          <p className="text-base text-gray-400 mt-1 flex items-center gap-1.5">
            <span className="text-premium-gold/80" aria-hidden>🕐</span>
            เวลานี้คุณกำลังทำงาน ({shiftLabel})
          </p>
        )}
      </div>
      <Link
        to="/บัญชีของฉัน"
        className="shrink-0 w-12 h-12 rounded-full border border-premium-gold/30 bg-premium-dark flex items-center justify-center text-premium-gold hover:bg-premium-gold/10 transition"
        title="บัญชีของฉัน"
        aria-label="ไปหน้าบัญชีของฉัน"
      >
        <svg className="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
          <path strokeLinecap="round" strokeLinejoin="round" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
          <path strokeLinecap="round" strokeLinejoin="round" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
        </svg>
      </Link>
    </section>
  );
}
