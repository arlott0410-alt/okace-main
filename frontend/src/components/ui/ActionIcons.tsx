/**
 * ไอคอนปุ่มดำเนินการ (แก้ไข, ลบ, ดาวน์โหลด ฯลฯ) — ใช้กับธีม premium-gold/dark
 * ใช้ currentColor ให้ parent กำหนดสีได้ (เช่น text-premium-gold, text-red-400)
 */
import type { ButtonHTMLAttributes, ReactNode } from 'react';

const SIZE = 18;
const viewBox = '0 0 24 24';

type IconOnlyButtonProps = ButtonHTMLAttributes<HTMLButtonElement> & {
  title: string;
  'aria-label'?: string;
  variant?: 'gold' | 'danger' | 'muted';
};

const iconBtnBase = 'inline-flex items-center justify-center rounded p-1 transition hover:opacity-90 focus:outline-none focus:ring-2 focus:ring-premium-gold/50';
const iconBtnVariants = {
  gold: 'text-premium-gold hover:bg-premium-gold/10',
  danger: 'text-red-400 hover:bg-red-400/10',
  muted: 'text-gray-400 hover:bg-white/5 hover:text-gray-200',
};

function IconButton({ title, variant = 'gold', className = '', children, ...props }: IconOnlyButtonProps & { children: ReactNode }) {
  return (
    <button
      type="button"
      title={title}
      aria-label={props['aria-label'] ?? title}
      className={`${iconBtnBase} ${iconBtnVariants[variant]} ${className}`}
      {...props}
    >
      {children}
    </button>
  );
}

const svgProps = { width: SIZE, height: SIZE, viewBox, fill: 'none', stroke: 'currentColor', strokeWidth: 1.8, strokeLinecap: 'round' as const, strokeLinejoin: 'round' as const };

export function IconEdit(props: { className?: string }) {
  return (
    <svg {...svgProps} className={props.className} aria-hidden>
      <path d="M11 4H4a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2v-7" />
      <path d="M18.5 2.5a2.12 2.12 0 013 3L12 15l-4 1 1-4 9.5-9.5z" />
    </svg>
  );
}

export function IconTrash(props: { className?: string }) {
  return (
    <svg {...svgProps} className={props.className} aria-hidden>
      <path d="M3 6h18M19 6v14a2 2 0 01-2 2H7a2 2 0 01-2-2V6M8 6V4a2 2 0 012-2h4a2 2 0 012 2v2" />
      <path d="M10 11v6M14 11v6" />
    </svg>
  );
}

export function IconDownload(props: { className?: string }) {
  return (
    <svg {...svgProps} className={props.className} aria-hidden>
      <path d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4" />
      <path d="M7 10l5 5 5-5M12 15V3" />
    </svg>
  );
}

export function IconPlus(props: { className?: string }) {
  return (
    <svg {...svgProps} className={props.className} aria-hidden>
      <path d="M12 5v14M5 12h14" />
    </svg>
  );
}

export function IconX(props: { className?: string }) {
  return (
    <svg {...svgProps} className={props.className} aria-hidden>
      <path d="M18 6L6 18M6 6l12 12" />
    </svg>
  );
}

export function IconCheck(props: { className?: string }) {
  return (
    <svg {...svgProps} className={props.className} aria-hidden>
      <path d="M20 6L9 15l-5-5" />
    </svg>
  );
}

/** ปุ่มไอคอนแก้ไข (ใช้ในแถวตาราง) */
export function BtnEdit({ onClick, title = 'แก้ไข', className = '', ...rest }: { onClick: () => void; title?: string; className?: string } & Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'onClick'>) {
  return (
    <IconButton type="button" title={title} variant="gold" onClick={onClick} className={className} {...rest}>
      <IconEdit />
    </IconButton>
  );
}

/** ปุ่มไอคอนลบ (ใช้ในแถวตาราง) */
export function BtnDelete({ onClick, title = 'ลบ', className = '', ...rest }: { onClick: () => void; title?: string; className?: string } & Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'onClick'>) {
  return (
    <IconButton type="button" title={title} variant="danger" onClick={onClick} className={className} {...rest}>
      <IconTrash />
    </IconButton>
  );
}

/** ปุ่มไอคอนยกเลิก (X) — ใช้ในแถวตาราง */
export function BtnCancel({ onClick, title = 'ยกเลิก', className = '', ...rest }: { onClick: () => void; title?: string; className?: string } & Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'onClick'>) {
  return (
    <IconButton type="button" title={title} variant="danger" onClick={onClick} className={className} {...rest}>
      <IconX />
    </IconButton>
  );
}

/** ปุ่มไอคอนดาวน์โหลด */
export function BtnDownload({ onClick, title = 'ดาวน์โหลด', className = '', ...rest }: { onClick: () => void; title?: string; className?: string } & Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'onClick'>) {
  return (
    <IconButton type="button" title={title} variant="gold" onClick={onClick} className={className} {...rest}>
      <IconDownload />
    </IconButton>
  );
}

/** ปุ่มไอคอนอนุมัติ (เช็ค) — ใช้สำหรับอนุมัติ/ปิดงาน ฯลฯ */
export function BtnApprove({ onClick, title = 'อนุมัติ', className = '', ...rest }: { onClick: () => void; title?: string; className?: string } & Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'onClick'>) {
  return (
    <IconButton type="button" title={title} variant="gold" onClick={onClick} className={className} {...rest}>
      <IconCheck />
    </IconButton>
  );
}
