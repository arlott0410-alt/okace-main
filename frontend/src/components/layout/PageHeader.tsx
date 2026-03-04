import type { ReactNode } from 'react';

interface PageHeaderProps {
  title: string;
  subtitle?: string;
  /** Primary actions (Add, Export, Publish) — compact buttons on the right */
  actions?: ReactNode;
  /** If true, header is sticky on long pages so actions remain visible */
  sticky?: boolean;
}

export default function PageHeader({ title, subtitle, actions, sticky = true }: PageHeaderProps) {
  return (
    <header
      className={`
        flex flex-wrap items-center justify-between gap-3 py-3
        ${sticky ? 'sticky top-0 z-10 bg-premium-dark/95 backdrop-blur-sm border-b border-premium-gold/10 -mx-4 px-4 md:-mx-6 md:px-6 mt-[-0.25rem]' : ''}
      `}
    >
      <div className="min-w-0">
        <h1 className="text-[18px] font-semibold text-premium-gold truncate">{title}</h1>
        {subtitle != null && subtitle !== '' && (
          <p className="text-gray-400 text-[12px] md:text-[13px] mt-0.5">{subtitle}</p>
        )}
      </div>
      {actions != null && <div className="flex items-center gap-2 shrink-0 flex-wrap">{actions}</div>}
    </header>
  );
}
