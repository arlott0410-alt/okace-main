import { useState, useEffect } from 'react';
import { NavLink } from 'react-router-dom';
import { useAuth } from '../lib/auth';

const SIDEBAR_PIN_KEY = 'okace_sidebar_pinned';
const SIDEBAR_WIDTH_COLLAPSED = 56;
const SIDEBAR_WIDTH_EXPANDED = 256;

type NavLinkItem = { to: string; label: string; icon: string; roles?: string[] };

const NAV_SECTIONS: { label: string; links: NavLinkItem[] }[] = [
  { label: 'ภาพรวม', links: [{ to: '/dashboard', label: 'แดชบอร์ด', icon: 'M4 6h16M4 12h16M4 18h10' }] },
  {
    label: 'เวลาเข้างาน / พัก',
    links: [{ to: '/จองพักอาหาร', label: 'จองเวลาพักทานอาหาร', icon: 'M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z', roles: ['instructor', 'staff'] }],
  },
  {
    label: 'ตารางและวันหยุด',
    links: [{ to: '/ตารางวันหยุด', label: 'ตารางวันหยุด', icon: 'M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z' }],
  },
  {
    label: 'ย้ายกะ / โอน',
    links: [
      { to: '/ย้ายกะจำนวนมาก', label: 'ย้ายกะ (จำนวนมาก)', icon: 'M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 7v2a2 2 0 002 2m0 0V5a2 2 0 012-2h14a2 2 0 012 2v2', roles: ['admin', 'manager', 'instructor_head'] },
    ],
  },
  {
    label: 'จัดตารางงาน',
    links: [{ to: '/ตารางงาน', label: 'ตารางงาน', icon: 'M9 17V7m0 10a2 2 0 01-2 2H5a2 2 0 01-2-2V7a2 2 0 012-2h2a2 2 0 012 2m0 10a2 2 0 002 2h2a2 2 0 002-2M9 7a2 2 0 012-2h2a2 2 0 012 2m0 10V7m0 10a2 2 0 002-2V7a2 2 0 00-2-2h-2a2 2 0 00-2 2v10a2 2 0 002 2z' }],
  },
  {
    label: 'จัดการ (หน้าที่ / งาน / เว็บ)',
    links: [
      { to: '/จัดหน้าที่', label: 'จัดหน้าที่', roles: ['admin', 'manager', 'instructor_head'], icon: 'M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2' },
      { to: '/ยืนยันตารางกะ', label: 'ยืนยันตารางกะ', roles: ['admin', 'manager', 'instructor_head'], icon: 'M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z' },
      { to: '/เว็บที่ดูแล', label: 'เว็บที่ดูแล', roles: ['admin', 'manager', 'instructor_head'], icon: 'M21 12a9 9 0 01-9 9m9-9a9 9 0 00-9-9m9 9H3m9 9a9 9 0 01-9-9m9 9c1.657 0 3-4.03 3-9s-1.343-9-3-9m0 18c-1.657 0-3-4.03-3-9s1.343-9 3-9m-9 9a9 9 0 019-9' },
      { to: '/เว็บที่ฉันดูแล', label: 'เว็บที่ฉันดูแล', roles: ['manager'], icon: 'M21 12a9 9 0 01-9 9m9-9a9 9 0 00-9-9m9 9H3m9 9a9 9 0 01-9-9m9 9c1.657 0 3-4.03 3-9s-1.343-9-3-9m0 18c-1.657 0-3-4.03-3-9s1.343-9 3-9m-9 9a9 9 0 019-9' },
      { to: '/จัดการสมาชิก', label: 'จัดการสมาชิก', roles: ['admin', 'manager', 'instructor_head'], icon: 'M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z' },
    ],
  },
  {
    label: 'ทรัพยากร',
    links: [
      { to: '/คลังเก็บไฟล์', label: 'คลังเก็บไฟล์', icon: 'M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z' },
      { to: '/กลุ่มงาน', label: 'กลุ่มงาน', icon: 'M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z' },
      { to: '/บุคคลที่สาม', label: 'บุคคลที่สาม', icon: 'M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v16h14z', roles: ['admin', 'manager', 'instructor_head', 'instructor', 'staff'] },
      { to: '/ประวัติ', label: 'ประวัติ', icon: 'M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z' },
    ],
  },
  { label: 'บัญชี', links: [{ to: '/บัญชีของฉัน', label: 'บัญชีของฉัน', icon: 'M16 7a4 4 0 11-8 0 4 4 0 018 0zM5 9a2 2 0 00-2 2v8a2 2 0 002 2h14a2 2 0 002-2v-8a2 2 0 00-2-2h-2m-4-1l-4 4m0 0l-4-4m4 4V4' }] },
  { label: 'ตั้งค่าระบบ', links: [{ to: '/ตั้งค่า', label: 'ตั้งค่า', roles: ['admin', 'manager'], icon: 'M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z M15 12a3 3 0 11-6 0 3 3 0 016 0z' }] },
];

function NavIcon({ d, className = '' }: { d: string; className?: string }) {
  return (
    <svg className={className} fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
      <path d={d} />
    </svg>
  );
}

export default function Nav() {
  const { profile } = useAuth();
  const [pinned, setPinned] = useState(() => localStorage.getItem(SIDEBAR_PIN_KEY) === 'true');
  const [hover, setHover] = useState(false);
  const [mobileOpen, setMobileOpen] = useState(false);

  useEffect(() => {
    localStorage.setItem(SIDEBAR_PIN_KEY, String(pinned));
  }, [pinned]);

  const expanded = pinned || hover;
  const collapsed = !expanded;

  const visibleSections = NAV_SECTIONS.map((section) => ({
    ...section,
    links: section.links.filter((l) => {
      if (!l.roles) return true;
      return profile && l.roles.includes(profile.role);
    }),
  })).filter((s) => s.links.length > 0);

  const SidebarContent = ({ isMobile = false }: { isMobile?: boolean }) => (
    <div className="py-3 space-y-4 overflow-y-auto overflow-x-hidden">
      {visibleSections.map((section) => (
        <div key={section.label}>
          {(!collapsed || isMobile) && (
            <div className="px-3 mb-1.5">
              <span className="text-[11px] font-semibold tracking-wider uppercase text-white truncate block">
                {section.label}
              </span>
            </div>
          )}
          <ul className="space-y-0.5">
            {section.links.map((link) => (
              <li key={link.to} className="px-2">
                <NavLink
                  to={link.to}
                  onClick={() => isMobile && setMobileOpen(false)}
                  className={({ isActive }) =>
                    `group relative flex items-center gap-3 rounded-xl py-2.5 px-3 transition-colors duration-200
                     ${collapsed && !isMobile ? 'justify-center px-2' : ''}
                     ${isActive
                       ? 'text-premium-gold'
                       : 'text-white hover:bg-premium-gold/10 hover:text-premium-gold/90'
                     }`
                  }
                >
                  {({ isActive }) => (
                    <>
                      {isActive && (
                        <span
                          className="absolute left-0 top-1/2 -translate-y-1/2 w-0.5 h-8 rounded-r bg-premium-gold origin-left transition-transform duration-300"
                          style={{ height: '60%' }}
                        />
                      )}
                      <span
                        className={`shrink-0 flex items-center justify-center w-8 h-8 rounded-lg transition-colors duration-200
                          ${isActive ? 'bg-premium-gold/25 text-premium-gold' : 'bg-premium-dark/60 text-white group-hover:bg-premium-gold/20 group-hover:text-premium-gold'}
                          ${collapsed && !isMobile ? 'w-9 h-9' : ''}`}
                      >
                        <NavIcon d={link.icon || 'M13 10V3L4 14h7v7l9-11h-7z'} className="w-4 h-4" />
                      </span>
                      {(!collapsed || isMobile) && (
                        <span className="font-semibold truncate">{link.label}</span>
                      )}
                    </>
                  )}
                </NavLink>
              </li>
            ))}
          </ul>
        </div>
      ))}
    </div>
  );

  return (
    <>
      {/* Desktop Sidebar: แถบแคบเมื่อปิด, โผล่เมื่อเอาเมาส์ไป หรือล็อคเปิด */}
      <aside
        className="hidden md:flex flex-col shrink-0 h-[calc(100vh-52px)] sticky top-[52px] z-20 bg-gradient-to-b from-premium-darker to-premium-dark border-r border-premium-gold/20 transition-[width] duration-300 ease-out"
        style={{ width: expanded ? SIDEBAR_WIDTH_EXPANDED : SIDEBAR_WIDTH_COLLAPSED }}
        onMouseEnter={() => setHover(true)}
        onMouseLeave={() => setHover(false)}
      >
        <div className="flex flex-col flex-1 min-h-0 min-w-0 w-full">
          <div
            className={`flex shrink-0 border-b border-premium-gold/10 ${collapsed ? 'flex-col items-center gap-2 py-3 px-0' : 'flex-row items-center justify-between px-3 py-3'}`}
          >
            {collapsed ? (
              <>
                <span className="flex items-center justify-center w-9 h-9 rounded-lg bg-premium-gold/10 text-premium-gold" title="เมนู">
                  <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                    <path strokeLinecap="round" strokeLinejoin="round" d="M4 6h16M4 12h16M4 18h16" />
                  </svg>
                </span>
                <button
                  type="button"
                  onClick={() => setPinned((p) => !p)}
                  className="p-1.5 rounded-lg text-gray-400 hover:text-premium-gold hover:bg-premium-gold/10 transition-all duration-200"
                  title={pinned ? 'ปลดล็อคเมนู' : 'ล็อคเมนูไว้'}
                >
                  {pinned ? (
                    <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
                    </svg>
                  ) : (
                    <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 11V7a4 4 0 118 0m-4 8v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2z" />
                    </svg>
                  )}
                </button>
              </>
            ) : (
              <>
                <span className="text-premium-gold/80 text-xs font-medium tracking-wider uppercase whitespace-nowrap">
                  เมนู
                </span>
                <button
                  type="button"
                  onClick={() => setPinned((p) => !p)}
                  className="p-1.5 rounded-lg text-gray-400 hover:text-premium-gold hover:bg-premium-gold/10 transition-all duration-200 shrink-0"
                  title={pinned ? 'ปลดล็อคเมนู' : 'ล็อคเมนูไว้'}
                >
                  {pinned ? (
                    <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
                    </svg>
                  ) : (
                    <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 11V7a4 4 0 118 0m-4 8v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2z" />
                    </svg>
                  )}
                </button>
              </>
            )}
          </div>
          <nav className="sidebar-scroll relative flex-1 min-h-0 overflow-y-auto overflow-x-hidden py-2 pr-0.5">
            <div className="absolute inset-0 left-0 w-px bg-gradient-to-b from-transparent via-premium-gold/10 to-transparent pointer-events-none" />
            <SidebarContent />
          </nav>
        </div>
      </aside>

      {/* Mobile: Toggle button */}
      <button
        type="button"
        onClick={() => setMobileOpen(true)}
        className="md:hidden fixed bottom-4 right-4 z-30 w-12 h-12 rounded-full bg-premium-gold text-premium-dark shadow-lg shadow-premium-gold/30 flex items-center justify-center active:scale-95 transition-transform"
        aria-label="เปิดเมนู"
      >
        <svg className="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 6h16M4 12h16M4 18h16" />
        </svg>
      </button>

      {/* Mobile: Overlay drawer */}
      <div
        className={`md:hidden fixed inset-0 z-40 transition-opacity duration-300 ${mobileOpen ? 'opacity-100' : 'opacity-0 pointer-events-none'}`}
        aria-hidden={!mobileOpen}
      >
        <div
          className="absolute inset-0 bg-black/60 backdrop-blur-sm"
          onClick={() => setMobileOpen(false)}
        />
        <aside
          className={`
            absolute left-0 top-0 bottom-0 w-72 max-w-[85vw] bg-gradient-to-b from-premium-darker to-premium-dark
            border-r border-premium-gold/20 shadow-2xl
            transform transition-transform duration-300 ease-out
            ${mobileOpen ? 'translate-x-0' : '-translate-x-full'}
          `}
        >
          <div className="flex items-center justify-between px-4 py-4 border-b border-premium-gold/20">
            <img src="/okace-logo.png" alt="OKACE" className="h-10 w-auto object-contain" />
            <button
              type="button"
              onClick={() => setMobileOpen(false)}
              className="p-2 rounded-lg text-gray-400 hover:text-white hover:bg-white/10"
            >
              <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>
          <SidebarContent isMobile />
        </aside>
      </div>
    </>
  );
}
