import type { ReactNode } from 'react';

interface PageCardProps {
  /** Section title in header row (14px bold) */
  title: string;
  /** Optional action buttons in header */
  actions?: ReactNode;
  children: ReactNode;
  /** Optional className for the card wrapper */
  className?: string;
}

/**
 * Standardized card/panel: border 1px gold/12, radius 10px, content spacing 12–16px.
 * Header: section title (14px bold) + action buttons.
 */
export default function PageCard({ title, actions, children, className = '' }: PageCardProps) {
  return (
    <section
      className={`
        rounded-[10px] border border-[rgba(255,215,0,0.12)] bg-[rgba(11,15,26,0.6)]
        ${className}
      `}
    >
      <div className="flex flex-wrap items-center justify-between gap-2 px-4 py-3 border-b border-premium-gold/10">
        <h2 className="text-[14px] font-bold text-gray-200">{title}</h2>
        {actions != null && <div className="flex items-center gap-2">{actions}</div>}
      </div>
      <div className="p-3 md:p-4 space-y-3 md:space-y-4">{children}</div>
    </section>
  );
}
