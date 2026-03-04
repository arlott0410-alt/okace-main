import { ButtonHTMLAttributes } from 'react';

type Variant = 'gold' | 'outline' | 'ghost' | 'danger';

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: Variant;
  loading?: boolean;
}

const styles: Record<Variant, string> = {
  gold: 'bg-premium-gold text-premium-dark hover:bg-premium-gold-light disabled:opacity-50',
  outline: 'border border-premium-gold text-premium-gold hover:bg-premium-gold/10',
  ghost: 'text-gray-300 hover:bg-white/5',
  danger: 'bg-red-600/80 text-white hover:bg-red-600',
};

export default function Button({ variant = 'gold', loading, className = '', children, disabled, ...props }: ButtonProps) {
  return (
    <button
      type="button"
      className={`px-4 py-2 rounded font-medium transition ${styles[variant]} ${className}`}
      disabled={disabled || loading}
      {...props}
    >
      {loading ? 'กำลังดำเนินการ...' : children}
    </button>
  );
}
