/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_SUPABASE_URL: string;
  readonly VITE_SUPABASE_ANON_KEY: string;
  readonly VITE_API_BASE?: string;
  readonly VITE_TURNSTILE_SITE_KEY?: string;
  readonly VITE_TURNSTILE_ENABLED?: string;
  readonly VITE_CF_IMAGE_BASE?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
