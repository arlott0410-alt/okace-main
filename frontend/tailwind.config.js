/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  theme: {
    extend: {
      colors: {
        premium: {
          dark: '#0B0F1A',
          darker: '#060910',
          gold: '#D4AF37',
          'gold-light': '#E5C76B',
          'gold-dark': '#B8962E',
        },
      },
      fontFamily: {
        sans: ['Sarabun', 'system-ui', 'sans-serif'],
      },
      keyframes: {
        'sidebar-in': {
          '0%': { opacity: '0', transform: 'translateX(-12px)' },
          '100%': { opacity: '1', transform: 'translateX(0)' },
        },
        'sidebar-glow': {
          '0%, 100%': { boxShadow: '0 0 0 0 rgba(212, 175, 55, 0)' },
          '50%': { boxShadow: '0 0 20px 2px rgba(212, 175, 55, 0.15)' },
        },
        'line-expand': {
          '0%': { transform: 'scaleX(0)', opacity: '0' },
          '100%': { transform: 'scaleX(1)', opacity: '1' },
        },
      },
      animation: {
        'sidebar-in': 'sidebar-in 0.35s ease-out forwards',
        'sidebar-glow': 'sidebar-glow 2s ease-in-out infinite',
        'line-expand': 'line-expand 0.25s ease-out',
      },
      transitionProperty: {
        'sidebar': 'width, padding, opacity',
      },
    },
  },
  plugins: [],
};
