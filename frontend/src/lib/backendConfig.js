/**
 * Centralized Backend Environment Resolver for ReGen React Frontend.
 *
 * Automatically chooses between:
 * - Local backend (`http://<PC_LAN_OR_LOCAL_HOST>:5006`) when reachable via `/api/health`
 * - Public backend (`https://regen.krishub.in`) when local backend is unreachable
 *   or when running on HTTPS / external networks.
 *
 * Handles automatic failover if local backend drops mid-session without duplicating
 * API clients or Socket.IO connections.
 */

export const PUBLIC_BACKEND_URL = (
  import.meta?.env?.VITE_PUBLIC_BACKEND_URL || 'https://regen.krishub.in'
).replace(/\/+$/, '');

export const PUBLIC_IP_BACKEND_URL = 'http://103.186.230.7';
export const LOCAL_BACKEND_PORT = Number(import.meta?.env?.VITE_LOCAL_BACKEND_PORT || 5006);
export const DEFAULT_LOCAL_LAN_IP = import.meta?.env?.VITE_LOCAL_LAN_IP || '192.168.1.38';

const HEALTH_TIMEOUT_MS = 1800;
const PROBE_COOLDOWN_MS = 15000;

const PRIVATE_LAN_HOST_REGEX =
  /^(192\.168\.\d+\.\d+|10\.\d+\.\d+\.\d+|172\.(1[6-9]|2\d|3[0-1])\.\d+\.\d+)$/i;

const KNOWN_REGEN_MEDIA_HOST_REGEX =
  /^https?:\/\/(localhost|127\.0\.0\.1|192\.168\.\d+\.\d+|10\.\d+\.\d+\.\d+|172\.(1[6-9]|2\d|3[0-1])\.\d+\.\d+|103\.186\.230\.7|regen\.krishub\.in)(:\d+)?$/i;

let _activeBaseUrl = inferInitialBaseUrl();
let _activeMode = _activeBaseUrl === PUBLIC_BACKEND_URL || _activeBaseUrl === PUBLIC_IP_BACKEND_URL
  ? 'public'
  : 'local';
let _initialized = false;
let _lastProbeAt = 0;
let _inFlightProbe = null;
const _listeners = new Set();

function normalizeBaseUrl(rawUrl) {
  if (!rawUrl) return PUBLIC_BACKEND_URL;
  return String(rawUrl).trim().replace(/\/+$/, '');
}

function isLanIpHostname(hostname) {
  return PRIVATE_LAN_HOST_REGEX.test(String(hostname || '').trim());
}

function inferInitialBaseUrl() {
  const envUrl = import.meta?.env?.VITE_BACKEND_URL;
  if (envUrl && String(envUrl).trim()) {
    return normalizeBaseUrl(envUrl);
  }
  if (typeof window === 'undefined') {
    return PUBLIC_BACKEND_URL;
  }
  const { protocol, hostname } = window.location;
  if (protocol === 'https:') {
    return PUBLIC_BACKEND_URL;
  }
  if (hostname === '103.186.230.7') {
    return PUBLIC_IP_BACKEND_URL;
  }
  if (isLanIpHostname(hostname)) {
    return `http://${hostname}:${LOCAL_BACKEND_PORT}`;
  }
  // Never default to localhost/127.0.0.1 for API calls; use https://regen.krishub.in.
  return PUBLIC_BACKEND_URL;
}

/**
 * Returns ordered non-localhost LAN backend candidate URLs eligible to probe.
 * Never uses `localhost` or `127.0.0.1`; always falls back to `https://regen.krishub.in`.
 */
export function getLocalCandidateUrls() {
  if (typeof window === 'undefined') return [];
  const envUrl = import.meta?.env?.VITE_BACKEND_URL;
  if (envUrl && String(envUrl).trim()) {
    return [normalizeBaseUrl(envUrl)];
  }
  const { protocol, hostname } = window.location;
  if (protocol === 'https:' || hostname === '103.186.230.7') {
    return [];
  }
  const forceLanProbe = String(import.meta?.env?.VITE_USE_LOCAL_BACKEND || '').toLowerCase() === 'true';
  if (!isLanIpHostname(hostname) && !forceLanProbe) {
    return [];
  }
  const host = isLanIpHostname(hostname) ? hostname : DEFAULT_LOCAL_LAN_IP;
  return [`http://${host}:${LOCAL_BACKEND_PORT}`];
}

export function getPublicFallbackUrl() {
  if (typeof window !== 'undefined' && window.location.hostname === '103.186.230.7') {
    return PUBLIC_IP_BACKEND_URL;
  }
  return PUBLIC_BACKEND_URL;
}

export function getActiveBackendUrl() {
  return _activeBaseUrl;
}

export function getActiveBackendMode() {
  return _activeMode;
}

export function subscribeBackendChange(listener) {
  _listeners.add(listener);
  return () => _listeners.delete(listener);
}

function setActiveBackend(url, mode) {
  const normalized = normalizeBaseUrl(url);
  const changed = normalized !== _activeBaseUrl || mode !== _activeMode;
  _activeBaseUrl = normalized;
  _activeMode = mode;
  if (changed) {
    const snapshot = { baseUrl: _activeBaseUrl, mode: _activeMode };
    _listeners.forEach((fn) => {
      try {
        fn(snapshot);
      } catch {}
    });
    if (typeof window !== 'undefined') {
      window.dispatchEvent(new CustomEvent('regen:backend-changed', { detail: snapshot }));
    }
  }
}

/**
 * Probes `<candidate>/api/health` with a short timeout to verify live backend availability.
 */
export async function probeBackendHealth(baseUrl, timeoutMs = HEALTH_TIMEOUT_MS) {
  const target = `${normalizeBaseUrl(baseUrl)}/api/health`;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(target, {
      method: 'GET',
      cache: 'no-store',
      signal: controller.signal,
      headers: { Accept: 'application/json' },
    });
    if (!res.ok) return false;
    const data = await res.json().catch(() => null);
    return Boolean(data && data.status === 'ok');
  } catch {
    return false;
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Probes local backend health; switches automatically to public domain when unreachable.
 */
export async function probeAndSelectBackend({ force = false } = {}) {
  const now = Date.now();
  if (_inFlightProbe) return _inFlightProbe;
  if (!force && _initialized && now - _lastProbeAt < PROBE_COOLDOWN_MS) {
    return { baseUrl: _activeBaseUrl, mode: _activeMode };
  }

  _inFlightProbe = (async () => {
    try {
      const localCandidates = getLocalCandidateUrls();
      for (const candidate of localCandidates) {
        const ok = await probeBackendHealth(candidate);
        if (ok) {
          setActiveBackend(candidate, 'local');
          _initialized = true;
          _lastProbeAt = Date.now();
          return { baseUrl: _activeBaseUrl, mode: _activeMode };
        }
      }

      const fallback = getPublicFallbackUrl();
      setActiveBackend(fallback, 'public');
      _initialized = true;
      _lastProbeAt = Date.now();
      return { baseUrl: _activeBaseUrl, mode: _activeMode };
    } finally {
      _inFlightProbe = null;
    }
  })();

  return _inFlightProbe;
}

let lifecycleAttached = false;
export async function initBackendConfig() {
  const result = await probeAndSelectBackend({ force: !_initialized });
  if (typeof window !== 'undefined' && !lifecycleAttached) {
    lifecycleAttached = true;
    window.addEventListener('online', () => {
      probeAndSelectBackend({ force: true });
    });
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'visible') {
        probeAndSelectBackend();
      }
    });
  }
  return result;
}

/**
 * Resolves relative `/api/...`, `/uploads/...`, `/assets/...` paths against the active backend.
 */
export function resolveApiUrl(input) {
  const s = String(input || '').trim();
  if (!s) return _activeBaseUrl;
  if (/^https?:\/\//i.test(s)) return s;
  const path = s.startsWith('/') ? s : `/${s}`;
  return `${_activeBaseUrl}${path}`;
}

/**
 * Resolves stored avatars, attachments, audio, video, and file download URLs onto the active backend.
 * Rewrites legacy local LAN or public domain media paths so media continues loading seamlessly across networks.
 */
export function resolveMediaUrl(rawUrl) {
  if (!rawUrl) return rawUrl;
  const s = String(rawUrl).trim();
  if (!s) return s;
  if (s.startsWith('data:') || s.startsWith('blob:')) return s;

  if (/^https?:\/\//i.test(s)) {
    try {
      const parsed = new URL(s);
      if (
        KNOWN_REGEN_MEDIA_HOST_REGEX.test(parsed.origin) &&
        /^\/(uploads|assets|profiles|api)\//i.test(parsed.pathname)
      ) {
        const cleanPath = parsed.pathname.replace(/^\/uploads\/assets\//, '/assets/');
        return `${_activeBaseUrl}${cleanPath}${parsed.search}`;
      }
    } catch {}
    return s;
  }

  const cleanPath = s.replace(/^\/uploads\/assets\//, '/assets/');
  if (
    cleanPath.startsWith('/assets/') ||
    cleanPath.startsWith('/uploads/') ||
    cleanPath.startsWith('/profiles/')
  ) {
    return `${_activeBaseUrl}${cleanPath}`;
  }
  return `${_activeBaseUrl}/assets/profiles/${cleanPath.replace(/^\/+/, '')}`;
}

/**
 * Fetch helper routing through the selected backend with automatic local->public failover.
 */
export async function apiFetch(urlOrPath, options = {}) {
  if (!_initialized) {
    await initBackendConfig();
  }
  const targetUrl = resolveApiUrl(urlOrPath);
  const canFailover =
    _activeMode === 'local' &&
    typeof urlOrPath === 'string' &&
    !/^https?:\/\//i.test(urlOrPath);

  try {
    const res = await fetch(targetUrl, options);
    if (canFailover && (res.status === 502 || res.status === 503 || res.status === 504)) {
      const updated = await probeAndSelectBackend({ force: true });
      if (updated.mode === 'public' && updated.baseUrl !== targetUrl) {
        return fetch(resolveApiUrl(urlOrPath), options);
      }
    }
    return res;
  } catch (err) {
    if (canFailover) {
      const updated = await probeAndSelectBackend({ force: true });
      if (updated.mode === 'public') {
        return fetch(resolveApiUrl(urlOrPath), options);
      }
    }
    throw err;
  }
}
