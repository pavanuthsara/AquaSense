import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Dev:   npm run dev   -> http://localhost:5173, /api is proxied to FastAPI on :8000
// Build: npm run build -> web/dist, served by FastAPI at http://localhost:8000
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      "/api": { target: process.env.AQUASENSE_API ?? "http://127.0.0.1:8000", changeOrigin: true },
    },
  },
  build: { outDir: "dist", emptyOutDir: true, chunkSizeWarningLimit: 800 }, // recharts is ~0.5 MB
});
