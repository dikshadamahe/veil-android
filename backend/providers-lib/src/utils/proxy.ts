import { FeatureMap, flags } from '@/entrypoint/utils/targets';
import { Stream } from '@/providers/streams';

// Default proxy URL for general purpose proxying
const DEFAULT_PROXY_URL = 'https://proxy.example.com';
// Default M3U8 proxy URL for HLS stream proxying
let CONFIGURED_M3U8_PROXY_URL = 'https://proxy.example.com';

/**
 * Set a custom M3U8 proxy URL to use for all M3U8 proxy requests
 * @param proxyUrl - The base URL of the M3U8 proxy
 */
export function setM3U8ProxyUrl(proxyUrl: string): void {
  CONFIGURED_M3U8_PROXY_URL = proxyUrl;
}

/**
 * Get the currently configured M3U8 proxy URL
 * @returns The configured M3U8 proxy URL
 */
export function getM3U8ProxyUrl(): string {
  return CONFIGURED_M3U8_PROXY_URL;
}

export function requiresProxy(stream: Stream): boolean {
  if (!stream.flags.includes(flags.CORS_ALLOWED) || !!(stream.headers && Object.keys(stream.headers).length > 0))
    return true;
  return false;
}

export function setupProxy(stream: Stream): Stream {
  const headers = stream.headers && Object.keys(stream.headers).length > 0 ? stream.headers : undefined;

  const options = {
    ...(stream.type === 'hls' && { depth: stream.proxyDepth ?? 0 }),
  };

  const payload: {
    type?: 'hls' | 'mp4';
    url?: string;
    headers?: Record<string, string>;
    options?: { depth?: 0 | 1 | 2 };
  } = {
    headers,
    options,
  };

  if (stream.type === 'hls') {
    payload.type = 'hls';
    payload.url = stream.playlist;
    stream.playlist = `${DEFAULT_PROXY_URL}?${new URLSearchParams({ payload: Buffer.from(JSON.stringify(payload)).toString('base64url') })}`;
  }

  if (stream.type === 'file') {
    payload.type = 'mp4';
    Object.entries(stream.qualities).forEach((entry) => {
      payload.url = entry[1].url;
      entry[1].url = `${DEFAULT_PROXY_URL}?${new URLSearchParams({ payload: Buffer.from(JSON.stringify(payload)).toString('base64url') })}`;
    });
  }

  stream.headers = {};
  stream.flags = [flags.CORS_ALLOWED];
  return stream;
}

/**
 * Creates a proxied M3U8 URL using the configured M3U8 proxy
 * @param url - The original M3U8 URL to proxy
 * @param features - Feature map to determine if local proxy (extension/native) is available
 * @param headers - Headers to include with the request
 * @returns The proxied M3U8 URL or original URL if local proxy is available
 */
export function createM3U8ProxyUrl(url: string, features?: FeatureMap, headers: Record<string, string> = {}): string {
  // If we have features and local proxy is available (no CORS restrictions), return original URL
  // The stream headers will handle the proxying through the extension/native environment
  if (features && !features.requires.includes(flags.CORS_ALLOWED)) {
    return url;
  }

  // Otherwise, use the external M3U8 proxy
  const encodedUrl = encodeURIComponent(url);
  const encodedHeaders = encodeURIComponent(JSON.stringify(headers));
  return `${CONFIGURED_M3U8_PROXY_URL}/m3u8-proxy?url=${encodedUrl}${headers ? `&headers=${encodedHeaders}` : ''}`;
}

/**
 * Updates an existing M3U8 proxy URL to use the currently configured proxy
 * @param url - The M3U8 proxy URL to update
 * @returns The updated M3U8 proxy URL
 */
export function updateM3U8ProxyUrl(url: string): string {
  if (url.includes('/m3u8-proxy?url=')) {
    return url.replace(/https:\/\/[^/]+\/m3u8-proxy/, `${CONFIGURED_M3U8_PROXY_URL}/m3u8-proxy`);
  }
  return url;
}
