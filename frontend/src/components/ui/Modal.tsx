import { ReactNode } from 'react';
import Button from './Button';

interface ModalProps {
  open: boolean;
  onClose: () => void;
  title: string;
  children: ReactNode;
  footer?: ReactNode;
}

export default function Modal({ open, onClose, title, children, footer }: ModalProps) {
  if (!open) return null;
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      <div className="absolute inset-0 bg-black/70" onClick={onClose} aria-hidden />
      <div className="relative bg-premium-darker border border-premium-gold/30 rounded-lg shadow-xl max-w-md w-full max-h-[90vh] overflow-hidden flex flex-col">
        <div className="px-4 py-3 border-b border-premium-gold/20 flex items-center justify-between">
          <h3 className="text-premium-gold font-semibold">{title}</h3>
          <button type="button" onClick={onClose} className="text-gray-400 hover:text-white">
            ×
          </button>
        </div>
        <div className="p-4 overflow-auto flex-1">{children}</div>
        {footer != null && <div className="px-4 py-3 border-t border-premium-gold/20 flex justify-end gap-2">{footer}</div>}
      </div>
    </div>
  );
}

export function ConfirmModal({
  open,
  onClose,
  onConfirm,
  title,
  message,
  confirmLabel = 'ยืนยัน',
  cancelLabel = 'ยกเลิก',
  variant = 'gold',
  loading,
}: {
  open: boolean;
  onClose: () => void;
  onConfirm: () => void | Promise<void>;
  title: string;
  message: ReactNode;
  confirmLabel?: string;
  cancelLabel?: string;
  variant?: 'gold' | 'danger';
  loading?: boolean;
}) {
  const handleConfirm = async () => {
    await onConfirm();
    onClose();
  };
  return (
    <Modal
      open={open}
      onClose={onClose}
      title={title}
      footer={
        <>
          <Button variant="ghost" onClick={onClose}>{cancelLabel}</Button>
          <Button variant={variant} onClick={handleConfirm} loading={loading}>{confirmLabel}</Button>
        </>
      }
    >
      {message}
    </Modal>
  );
}
