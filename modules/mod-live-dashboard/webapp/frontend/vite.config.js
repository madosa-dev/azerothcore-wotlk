import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  build: {
    // server.py serves this directory as static files alongside its /api/* routes.
    outDir: '../dist',
    emptyOutDir: true,
  },
  server: {
    // `npm run dev` proxies API calls to the Python backend (run separately: `python3 ../server.py`).
    proxy: {
      '/api': 'http://127.0.0.1:8787',
      '/tiles': 'http://127.0.0.1:8787',
      '/icons': 'http://127.0.0.1:8787',
    },
  },
})
