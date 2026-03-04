import { useState, useEffect, useRef } from 'react';

/**
 * Returns a value that updates only after `delayMs` of no changes (debounced).
 * Use for search/filter inputs to avoid excessive re-renders and query spam.
 */
export function useDebouncedValue<T>(value: T, delayMs: number): T {
  const [debounced, setDebounced] = useState(value);
  const prevValue = useRef(value);
  const timeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    if (value === prevValue.current) return;
    prevValue.current = value;
    if (timeoutRef.current) clearTimeout(timeoutRef.current);
    timeoutRef.current = setTimeout(() => {
      setDebounced(value);
      timeoutRef.current = null;
    }, delayMs);
    return () => {
      if (timeoutRef.current) clearTimeout(timeoutRef.current);
    };
  }, [value, delayMs]);

  // If value matches what we last debounced, keep in sync (e.g. external reset)
  if (value === debounced) return debounced;
  return debounced;
}
