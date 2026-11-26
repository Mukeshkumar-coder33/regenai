import { fileURLToPath, URL } from 'url';
import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';
import environment from 'vite-plugin-environment';

process.env.STORAGE_GATEWAY_URL =
  process.env.STORAGE_GATEWAY_URL || 'https://blob.caffeine.ai';

const PROXY_TARGET = process.env.VITE_PROXY_TARGET || 'https://regen.krishub.in';

export default defineConfig({
  logLevel: 'info',

  server: {
    host: '::',          // listens on IPv6 & IPv4 LAN/Nginx
    port: 2000,
    strictPort: false,
    proxy: {
      '/api': {
        target: PROXY_TARGET,
        changeOrigin: true,
        secure: true,
        timeout: 30000,
        proxyTimeout: 30000,
        configure: (proxy) => {
          proxy.on('error', (err, req, res) => {
            if (res && !res.headersSent && typeof res.writeHead === 'function') {
              res.writeHead(503, { 'Content-Type': 'application/json' });
              res.end(JSON.stringify({ maintenance: true, portDown: true, message: 'Server Under Maintenance' }));
            }
          });
        }
      },
      '/ws': {
        target: PROXY_TARGET,
        changeOrigin: true,
        secure: true,
        ws: true,
        configure: (proxy) => {
          proxy.on('error', () => {});
        }
      },
      '/socket.io': {
        target: PROXY_TARGET,
        changeOrigin: true,
        secure: true,
        ws: true
      },
      '/assets': {
        target: PROXY_TARGET,
        changeOrigin: true,
        secure: true
      },
      '/uploads': {
        target: PROXY_TARGET,
        changeOrigin: true,
        secure: true
      }
    },
    allowedHosts: true   // allow regen.krishub.in, subdomains, and LAN hosts
  },

  build: {
    emptyOutDir: true,
    sourcemap: false,
    minify: false
  },

  css: {
    postcss: './postcss.config.js'
  },

  optimizeDeps: {
    esbuildOptions: {
      define: {
        global: 'globalThis'
      }
    }
  },

  plugins: [
    environment('all', { prefix: 'CANISTER_' }),
    environment('all', { prefix: 'DFX_' }),
    environment(['STORAGE_GATEWAY_URL']),
    react()
  ],

  resolve: {
    alias: [
      {
        find: 'declarations',
        replacement: fileURLToPath(new URL('../declarations', import.meta.url))
      },
      {
        find: '@',
        replacement: fileURLToPath(new URL('./src', import.meta.url))
      }
    ],
    dedupe: ['@dfinity/agent']
  }
});
