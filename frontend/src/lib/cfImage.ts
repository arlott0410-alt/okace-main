/**
 * Optional Cloudflare Image Resizing / Transformations.
 * If VITE_CF_IMAGE_BASE is not set, returns the original URL unchanged.
 * Do not replace existing image URLs across the app; use only where you opt in.
 */

export interface CfImageOptions {
  width?: number;
  height?: number;
  quality?: number;
  format?: 'auto' | 'webp' | 'avif' | 'json' | 'jpeg' | 'png' | 'gif';
}

function getBase(): string {
  const base = import.meta.env.VITE_CF_IMAGE_BASE;
  if (typeof base !== 'string' || !base.trim()) return '';
  return base.replace(/\/$/, '');
}

/**
 * Builds a Cloudflare Image Resizing URL for the given original URL and options.
 * If base is not configured or empty, returns originalUrl unchanged.
 */
export function buildCfImageUrl(originalUrl: string, options: CfImageOptions): string {
  const base = getBase();
  if (!base) return originalUrl;
  const parts: string[] = [];
  if (options.width != null && Number.isFinite(options.width)) parts.push(`width=${options.width}`);
  if (options.height != null && Number.isFinite(options.height)) parts.push(`height=${options.height}`);
  if (options.quality != null && Number.isFinite(options.quality)) parts.push(`quality=${options.quality}`);
  if (options.format) parts.push(`format=${options.format}`);
  if (parts.length === 0) return originalUrl;
  const opts = parts.join(',');
  const prefix = base.startsWith('http') ? base : `https://${base}`;
  const path = originalUrl.startsWith('http') ? originalUrl : (originalUrl.startsWith('/') ? originalUrl : `/${originalUrl}`);
  return `${prefix}/cdn-cgi/image/${opts}/${path}`;
}
