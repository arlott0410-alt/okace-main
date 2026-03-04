import { ReactNode } from 'react';
import Button from './Button';

export interface PageModalProps {
  open: boolean;
  onClose: () => void;
  title: string;
  children: ReactNode;
  footer?: ReactNode;
  onCancel?: () => void;
  onSave?: () => void | Promise<void>;
  saveLabel?: string;
  saveLoading?: boolean;
}

/**
 * Modal มาตรฐานสำหรับฟอร์มใหญ่: max-w-4xl, sticky header/footer, body เลื่อนได้
 * ใช้ .okace-scroll ใน body
 */
export default function PageModal({
  open,
  onClose,
  title,
  children,
  footer,
  onCancel,
  onSave,
  saveLabel = 'บันทึก',
  saveLoading = false,
}: PageModalProps) {
  if (!open) return null;

  const defaultFooter =
    (footer == null && (onCancel != null || onSave != null))
      ? (
          <>
            {onCancel && <Button variant="ghost" onClick={onCancel}>ยกเลิก</Button>}
            {onSave && <Button variant="gold" onClick={onSave} loading={saveLoading}>{saveLabel}</Button>}
          </>
        )
      : null;

  const resolvedFooter = footer ?? defaultFooter;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-2 sm:p-4">
      <div className="absolute inset-0 bg-black/70" onClick={onClose} aria-hidden />
      <div
        className="relative flex flex-col w-full max-w-4xl max-h-[calc(100vh-2rem)] rounded-xl border border-premium-gold/30 bg-premium-darker shadow-xl overflow-hidden"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Sticky header */}
        <div className="shrink-0 flex items-center justify-between px-4 py-3 border-b border-premium-gold/20 bg-premium-darker/80">
          <h3 className="text-premium-gold font-semibold text-lg truncate pr-2">{title}</h3>
          <button
            type="button"
            onClick={onClose}
            className="shrink-0 w-9 h-9 flex items-center justify-center rounded-lg text-gray-400 hover:text-white hover:bg-premium-gold/10 transition-colors"
            aria-label="ปิด"
          >
            ×
          </button>
        </div>

        {/* Scrollable body */}
        <div
          className="flex-1 overflow-auto okace-scroll min-h-0"
          style={{ maxHeight: 'calc(100vh - 180px)' }}
        >
          <div className="p-4">{children}</div>
        </div>

        {/* Sticky footer */}
        {resolvedFooter != null && (
          <div className="shrink-0 px-4 py-3 border-t border-premium-gold/20 flex justify-end gap-2 bg-premium-darker/80">
            {resolvedFooter}
          </div>
        )}
      </div>
    </div>
  );
}
