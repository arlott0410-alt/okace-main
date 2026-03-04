import type { ReactNode } from 'react';

interface ContentAreaProps {
  children: ReactNode;
  /** Max width 1440px, padding 16–20px, internal scroll */
  className?: string;
}

/**
 * Content area: max-width 1440px, 16–20px padding. Used inside Layout main.
 */
export default function ContentArea({ children, className = '' }: ContentAreaProps) {
  return (
    <div className={`w-full max-w-[1440px] mx-auto px-4 md:px-5 lg:px-[20px] ${className}`}>
      {children}
    </div>
  );
}
