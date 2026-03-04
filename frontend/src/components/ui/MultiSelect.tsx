import { useState, useRef, useEffect } from 'react';

export type MultiSelectOption = { id: string; label: string };

interface MultiSelectProps {
  options: MultiSelectOption[];
  value: string[];
  onChange: (ids: string[]) => void;
  label?: string;
  placeholder?: string;
  /** ค่า id พิเศษสำหรับ "ทั้งหมด" (เลือกแล้ว = ไม่กรอง) */
  allId?: string;
  allLabel?: string;
  /** สูงสุดของรายการ (scroll) */
  maxHeight?: string;
  className?: string;
  disabled?: boolean;
  /** แสดง selected เป็น chips (ลบได้ด้วย ×) */
  showChips?: boolean;
  /** แสดงช่องค้นหาใน dropdown */
  searchable?: boolean;
}

/**
 * ตัวเลือกหลายรายการ — dropdown แบบ checkbox list เข้ากับธีม premium dark
 */
export default function MultiSelect({
  options,
  value,
  onChange,
  label,
  placeholder = 'เลือก...',
  allId,
  allLabel = 'ทั้งหมด',
  maxHeight = '12rem',
  className = '',
  disabled = false,
  showChips = false,
  searchable = false,
}: MultiSelectProps) {
  const [open, setOpen] = useState(false);
  const [search, setSearch] = useState('');
  const containerRef = useRef<HTMLDivElement>(null);

  const filteredOptions = searchable && search.trim()
    ? options.filter((o) => o.label.toLowerCase().includes(search.trim().toLowerCase()))
    : options;

  const hasAll = allId != null;
  const isAllSelected = hasAll && value.includes(allId);
  const selectedCount = value.filter((id) => id !== allId).length;

  const getOptionLabel = (id: string) => options.find((o) => o.id === id)?.label ?? '—';
  const displayText =
    isAllSelected || (hasAll && value.length === 0)
      ? allLabel
      : selectedCount === 0
        ? placeholder
        : selectedCount === 1
          ? getOptionLabel(value[0])
          : `เลือกแล้ว ${selectedCount} รายการ`;

  const toggle = (id: string) => {
    if (id === allId) {
      onChange(value.includes(allId) ? [] : [allId]);
      return;
    }
    const next = value.includes(id) ? value.filter((x) => x !== id) : [...value.filter((x) => x !== allId), id];
    onChange(next.length ? next : (hasAll ? [allId] : []));
  };

  const removeChip = (id: string) => {
    if (id === allId) {
      onChange([]);
      return;
    }
    onChange(value.filter((x) => x !== id));
  };

  const selectedForChips = value.filter((id) => id !== allId);

  useEffect(() => {
    const onOutside = (e: MouseEvent) => {
      if (containerRef.current && !containerRef.current.contains(e.target as Node)) setOpen(false);
    };
    if (open) {
      document.addEventListener('mousedown', onOutside);
      return () => document.removeEventListener('mousedown', onOutside);
    }
  }, [open]);

  return (
    <div ref={containerRef} className={`relative ${className}`}>
      {label && (
        <label className="block text-gray-400 text-sm mb-1">{label}</label>
      )}
      <button
        type="button"
        onClick={() => !disabled && setOpen((o) => !o)}
        disabled={disabled}
        className="w-full text-left bg-premium-dark border border-premium-gold/30 rounded px-3 py-2 text-white placeholder-gray-500 flex items-center justify-between gap-2 disabled:opacity-50 disabled:cursor-not-allowed hover:border-premium-gold/50 focus:outline-none focus:ring-1 focus:ring-premium-gold/50"
      >
        <span className="truncate">{displayText}</span>
        <svg className={`w-4 h-4 shrink-0 text-gray-400 transition-transform ${open ? 'rotate-180' : ''}`} fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
        </svg>
      </button>
      {open && (
        <div
          className="absolute z-50 mt-1 w-full min-w-[10rem] rounded-lg border border-premium-gold/30 bg-premium-dark shadow-xl py-1"
          style={{ maxHeight: searchable ? 'none' : maxHeight }}
        >
          {searchable && (
            <div className="px-2 pb-1 sticky top-0 bg-premium-dark z-10">
              <input
                type="text"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder="ค้นหา..."
                className="w-full rounded border border-premium-gold/30 bg-premium-darker px-2 py-1.5 text-sm text-white placeholder-gray-500 focus:outline-none focus:ring-1 focus:ring-premium-gold/50"
              />
            </div>
          )}
          <div className={`overflow-y-auto okace-scroll ${searchable ? 'max-h-48' : ''}`} style={searchable ? {} : { maxHeight: `calc(${maxHeight} - 0.5rem)` }}>
            {hasAll && (
              <label className="flex items-center gap-2 px-3 py-2 cursor-pointer hover:bg-premium-gold/10 text-gray-200">
                <input
                  type="checkbox"
                  checked={isAllSelected || (value.length === 0)}
                  onChange={() => toggle(allId)}
                  className="rounded border-premium-gold/50 text-premium-gold focus:ring-premium-gold/30"
                />
                <span className="text-sm">{allLabel}</span>
              </label>
            )}
            {filteredOptions.map((opt) => {
              const checked = value.includes(opt.id);
              return (
                <label key={opt.id} className="flex items-center gap-2 px-3 py-2 cursor-pointer hover:bg-premium-gold/10 text-gray-200">
                  <input
                    type="checkbox"
                    checked={checked}
                    onChange={() => toggle(opt.id)}
                    className="rounded border-premium-gold/50 text-premium-gold focus:ring-premium-gold/30"
                  />
                  <span className="text-sm truncate">{opt.label}</span>
                </label>
              );
            })}
          </div>
        </div>
      )}
      {showChips && selectedForChips.length > 0 && (
        <div className="mt-1.5 flex flex-wrap gap-1.5">
          {selectedForChips.map((id) => {
            const opt = options.find((o) => o.id === id);
            const label = id === allId ? allLabel : (opt?.label ?? '—');
            return (
              <span
                key={id}
                className="inline-flex items-center gap-1 rounded-lg border border-premium-gold/30 bg-premium-gold/10 px-2 py-0.5 text-xs text-premium-gold"
              >
                {label}
                <button
                  type="button"
                  onClick={() => removeChip(id)}
                  className="hover:text-white focus:outline-none"
                  aria-label="ลบ"
                >
                  ×
                </button>
              </span>
            );
          })}
        </div>
      )}
    </div>
  );
}
