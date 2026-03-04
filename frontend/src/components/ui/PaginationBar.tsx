/**
 * Reusable server-side pagination bar — ใช้กับ theme premium-gold/dark
 * Props: page, pageSize, totalCount, onPageChange, onPageSizeChange
 * UI: Prev/Next, เลขหน้า, "แสดง x–y จากทั้งหมด N", ตัวเลือก pageSize (10/20/50)
 */
type PaginationBarProps = {
  page: number;
  pageSize: number;
  totalCount: number;
  onPageChange: (page: number) => void;
  onPageSizeChange?: (pageSize: number) => void;
  /** ตัวเลือกจำนวนต่อหน้า (default [10, 20, 50]) */
  pageSizeOptions?: number[];
  /** ปิดการแสดงตัวเลือก pageSize (default false) */
  hidePageSize?: boolean;
  /** ข้อความแทน "รายการ" (default "รายการ") */
  itemLabel?: string;
};

export default function PaginationBar({
  page,
  pageSize,
  totalCount,
  onPageChange,
  onPageSizeChange,
  pageSizeOptions = [10, 20, 50],
  hidePageSize = false,
  itemLabel = 'รายการ',
}: PaginationBarProps) {
  const totalPages = Math.max(1, Math.ceil(totalCount / pageSize));
  const effectivePage = Math.min(Math.max(1, page), totalPages);
  const fromItem = totalCount === 0 ? 0 : (effectivePage - 1) * pageSize + 1;
  const toItem = Math.min(effectivePage * pageSize, totalCount);

  const showPrev = effectivePage > 1;
  const showNext = effectivePage < totalPages;

  /** แสดงเลขหน้าที่กดได้ (มากสุด 7 ตัว: 1 ... 4 5 6 ... 12) */
  const pageNumbers: (number | 'ellipsis')[] = [];
  if (totalPages <= 7) {
    for (let i = 1; i <= totalPages; i++) pageNumbers.push(i);
  } else {
    pageNumbers.push(1);
    if (effectivePage > 3) pageNumbers.push('ellipsis');
    const start = Math.max(2, effectivePage - 1);
    const end = Math.min(totalPages - 1, effectivePage + 1);
    for (let i = start; i <= end; i++) pageNumbers.push(i);
    if (effectivePage < totalPages - 2) pageNumbers.push('ellipsis');
    if (totalPages > 1) pageNumbers.push(totalPages);
  }

  return (
    <div className="flex flex-wrap items-center justify-between gap-2 mt-2 px-1 text-sm text-gray-400">
      <span>
        แสดง {fromItem}–{toItem} จากทั้งหมด {totalCount.toLocaleString()} {itemLabel}
      </span>
      <div className="flex flex-wrap items-center gap-2">
        {!hidePageSize && onPageSizeChange && (
          <div className="flex items-center gap-1.5">
            <label className="text-gray-400 text-sm whitespace-nowrap">แสดง</label>
            <select
              value={pageSize}
              onChange={(e) => {
                onPageSizeChange(Number(e.target.value));
                onPageChange(1);
              }}
              className="bg-premium-darker border border-premium-gold/30 rounded px-2 py-1.5 text-white text-sm min-w-[4rem]"
            >
              {pageSizeOptions.map((n) => (
                <option key={n} value={n}>{n}</option>
              ))}
            </select>
            <span className="text-gray-400 text-sm">ต่อหน้า</span>
          </div>
        )}
        <div className="flex items-center gap-1">
          <button
            type="button"
            onClick={() => onPageChange(effectivePage - 1)}
            disabled={!showPrev}
            className="px-2 py-1.5 rounded border border-premium-gold/30 text-premium-gold disabled:opacity-50 disabled:cursor-not-allowed hover:bg-premium-gold/10 transition"
          >
            ก่อนหน้า
          </button>
          <span className="flex items-center gap-0.5">
            {pageNumbers.map((n, i) =>
              n === 'ellipsis' ? (
                <span key={`e-${i}`} className="px-1.5 text-gray-500">…</span>
              ) : (
                <button
                  key={n}
                  type="button"
                  onClick={() => onPageChange(n)}
                  className={`min-w-[2rem] px-1.5 py-1 rounded border transition ${
                    n === effectivePage
                      ? 'border-premium-gold bg-premium-gold/20 text-premium-gold'
                      : 'border-premium-gold/30 text-gray-300 hover:bg-premium-gold/10'
                  }`}
                >
                  {n}
                </button>
              )
            )}
          </span>
          <button
            type="button"
            onClick={() => onPageChange(effectivePage + 1)}
            disabled={!showNext}
            className="px-2 py-1.5 rounded border border-premium-gold/30 text-premium-gold disabled:opacity-50 disabled:cursor-not-allowed hover:bg-premium-gold/10 transition"
          >
            ถัดไป
          </button>
        </div>
      </div>
    </div>
  );
}
