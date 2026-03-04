import { useState, useRef, useEffect } from 'react';
import { Link } from 'react-router-dom';
import { useAuth } from '../lib/auth';

const ROLE_LABEL: Record<string, string> = {
  admin: 'ผู้ดูแลระบบ',
  manager: 'ผู้จัดการ',
  instructor_head: 'หัวหน้าพนักงานประจำ',
  instructor: 'พนักงานประจำ',
  staff: 'พนักงานออนไลน์',
};

/** Role badge color: gold Admin/Manager, silver Head, bronze Instructor/Staff */
const ROLE_BADGE_CLASS: Record<string, string> = {
  admin: 'bg-premium-gold/25 text-premium-gold border-premium-gold/40',
  manager: 'bg-premium-gold/25 text-premium-gold border-premium-gold/40',
  instructor_head: 'bg-gray-400/20 text-gray-300 border-gray-500/50',
  instructor: 'bg-amber-700/25 text-amber-400/90 border-amber-600/40',
  staff: 'bg-amber-700/25 text-amber-400/90 border-amber-600/40',
};

function displayNameForHeader(profile: { role?: string; display_name?: string | null; email?: string; shift?: { name?: string } | null } | null): string {
  if (!profile) return '';
  const base = profile.display_name || profile.email || '';
  if (profile.role === 'manager') return base ? `QL-${base}` : 'QL-';
  const branchCode = (profile as { branch?: { code?: string; name?: string } })?.branch?.code
    ?? (profile as { branch?: { name?: string } })?.branch?.name ?? null;
  const isHead = profile?.role === 'instructor_head';
  return branchCode ? `${branchCode}-${base}${isHead ? '-TT' : ''}` : base;
}

export default function Header() {
  const { profile, signOut } = useAuth();
  const [userMenuOpen, setUserMenuOpen] = useState(false);
  const userMenuRef = useRef<HTMLDivElement>(null);

  const roleLabel = profile?.role ? (ROLE_LABEL[profile.role] ?? 'พนักงานออนไลน์') : '';
  const nameWithBranch = displayNameForHeader(profile);

  useEffect(() => {
    function handleClickOutside(e: MouseEvent) {
      if (userMenuRef.current && !userMenuRef.current.contains(e.target as Node)) {
        setUserMenuOpen(false);
      }
    }
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  return (
    <header className="sticky top-0 z-30 flex items-center justify-between gap-2 px-4 py-2.5 bg-premium-darker border-b border-premium-gold/20">
      <div className="flex items-center min-w-0">
        <img src="/okace-logo.png" alt="OKACE" className="h-11 w-auto shrink-0 object-contain" />
      </div>

      <div className="flex items-center gap-2 md:gap-3 shrink-0">
        {/* Role badge */}
        {profile?.role && (
          <span
            className={`hidden sm:inline-flex items-center px-2 py-0.5 rounded text-[12px] font-medium border ${ROLE_BADGE_CLASS[profile.role] ?? 'bg-gray-500/20 text-gray-400 border-gray-500/30'}`}
            title={roleLabel}
          >
            {roleLabel}
          </span>
        )}

        {/* User menu */}
        <div className="relative" ref={userMenuRef}>
          <button
            type="button"
            onClick={() => setUserMenuOpen((o) => !o)}
            className="flex items-center gap-2 px-2 py-1.5 rounded-lg text-gray-300 text-[13px] hover:bg-premium-gold/10 hover:text-premium-gold"
            aria-expanded={userMenuOpen}
            aria-haspopup="true"
          >
            <span className="max-w-[120px] truncate hidden sm:inline">{nameWithBranch || 'บัญชี'}</span>
            <svg className="w-4 h-4 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" /></svg>
          </button>
          {userMenuOpen && (
            <div className="absolute right-0 top-full mt-1 py-1 w-44 rounded-lg border border-premium-gold/20 bg-premium-darker shadow-xl z-50">
              <Link
                to="/บัญชีของฉัน"
                onClick={() => setUserMenuOpen(false)}
                className="block px-3 py-2 text-[13px] text-gray-300 hover:bg-white/5 hover:text-premium-gold"
              >
                บัญชีของฉัน
              </Link>
              <button
                type="button"
                onClick={() => { setUserMenuOpen(false); signOut(); }}
                className="block w-full text-left px-3 py-2 text-[13px] text-gray-400 hover:bg-white/5 hover:text-red-400"
              >
                ออกจากระบบ
              </button>
            </div>
          )}
        </div>
      </div>
    </header>
  );
}
