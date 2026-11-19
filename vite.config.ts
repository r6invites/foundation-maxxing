/// <reference types="vitest" />
import { defineConfig, loadEnv } from 'vite';
import react from '@vitejs/plugin-react';

// VITE_BASE_PATH is the single switch for where the site is served from.
//   GitHub Pages repo sub-path:  /foundation-maxxing/
//   Root custom domain:          /
// The default './' (relative assets) works for both because the app uses HashRouter.
export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, '.', 'VITE_');
  return {
    base: env.VITE_BASE_PATH || './',
    plugins: [react()],
    test: {
      environment: 'node',
      include: ['src/**/*.test.ts'],
    },
  };
});
