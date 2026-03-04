import { createContext, useContext, useState, useCallback, useEffect } from 'react';

type ToastVariant = 'success' | 'error' | 'info';

type ToastState = {
  message: string;
  variant: ToastVariant;
} | null;

type ToastContextValue = {
  show: (message: string, variant?: ToastVariant) => void;
};

const ToastContext = createContext<ToastContextValue | null>(null);

const AUTO_HIDE_MS = 3000;

export function ToastProvider({ children }: { children: React.ReactNode }) {
  const [toast, setToast] = useState<ToastState>(null);

  useEffect(() => {
    if (!toast) return;
    const t = setTimeout(() => setToast(null), AUTO_HIDE_MS);
    return () => clearTimeout(t);
  }, [toast]);

  const show = useCallback((message: string, variant: ToastVariant = 'success') => {
    setToast({ message, variant });
  }, []);

  return (
    <ToastContext.Provider value={{ show }}>
      {children}
      {toast && (
        <div
          role="alert"
          className="fixed bottom-4 right-4 z-[100] max-w-sm rounded-lg border px-4 py-3 shadow-lg"
          style={{
            backgroundColor: '#1A1A1A',
            borderColor: toast.variant === 'error' ? 'rgba(239,68,68,0.5)' : toast.variant === 'info' ? 'rgba(59,130,246,0.5)' : 'rgba(212,175,55,0.5)',
            color: toast.variant === 'error' ? '#FCA5A5' : toast.variant === 'info' ? '#93C5FD' : '#D4AF37',
          }}
        >
          {toast.message}
        </div>
      )}
    </ToastContext.Provider>
  );
}

export function useToast(): ToastContextValue {
  const ctx = useContext(ToastContext);
  if (!ctx) return { show: () => {} };
  return ctx;
}
