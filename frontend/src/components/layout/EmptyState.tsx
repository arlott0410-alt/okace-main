import type { ReactNode } from 'react';

interface EmptyStateProps {
  message: string;
  /** Optional icon or illustration */
  icon?: ReactNode;
}

/**
 * Meaningful empty state for cards/tables when there is no data.
 */
export default function EmptyState({ message, icon }: EmptyStateProps) {
  return (
    <div className="flex flex-col items-center justify-center py-8 px-4 text-center text-gray-400 text-[13px]">
      {icon != null && <div className="mb-2 text-premium-gold/60">{icon}</div>}
      <p>{message}</p>
    </div>
  );
}
