import { NotFoundError } from '@/utils/errors';

import { makeEmbed } from '../base';

const VIDNEST_SERVERS = ['hollymoviehd', 'allmovies'] as const;

const baseUrl = 'https://second.vidnest.fun';
const PASSPHRASE = 'A7kP9mQeXU2BWcD4fRZV+Sg8yN0/M5tLbC1HJQwYe6pOKFaE3vTnPZsRuYdVmLq2';

const serverConfigs: Record<string, { streamDomains: string[] | null; origin: string; referer: string }> = {
  hollymoviehd: {
    streamDomains: ['pkaystream.cc', 'flashstream.cc'],
    origin: 'https://flashstream.cc',
    referer: 'https://flashstream.cc/',
  },
  allmovies: {
    streamDomains: null,
    origin: '',
    referer: '',
  },
};

function base64ToUint8Array(base64: string): Uint8Array {
  const binaryString = atob(base64);
  const bytes = new Uint8Array(binaryString.length);
  for (let i = 0; i < binaryString.length; i++) {
    bytes[i] = binaryString.charCodeAt(i);
  }
  return bytes;
}

async function decryptVidnestData(encryptedBase64: string): Promise<any> {
  const encryptedBytes = base64ToUint8Array(encryptedBase64);
  const iv = encryptedBytes.slice(0, 12);
  const ciphertext = encryptedBytes.slice(12, -16);
  const tag = encryptedBytes.slice(-16);
  const keyData = base64ToUint8Array(PASSPHRASE).slice(0, 32);

  const cryptoKey = await crypto.subtle.importKey('raw', keyData, { name: 'AES-GCM' }, false, ['decrypt']);

  const combined = new Uint8Array(ciphertext.length + tag.length);
  combined.set(ciphertext, 0);
  combined.set(tag, ciphertext.length);

  const decrypted = await crypto.subtle.decrypt({ name: 'AES-GCM', iv }, cryptoKey, combined);
  return JSON.parse(new TextDecoder('utf-8').decode(decrypted));
}

export function makeVidnestEmbed(id: string, rank: number = 100) {
  const config = serverConfigs[id];

  return makeEmbed({
    id: `vidnest-${id}`,
    name: `Vidnest ${id}`,
    rank,
    disabled: false,
    flags: [],
    async scrape(ctx) {
      const query = JSON.parse(ctx.url);
      const { type, tmdbId, season, episode } = query;

      const endpoint = type === 'movie' ? `/${id}/movie/${tmdbId}` : `/${id}/tv/${tmdbId}/${season}/${episode}`;

      const res = await ctx.proxiedFetcher<{ data?: string }>(endpoint, {
        baseUrl,
        headers: {
          'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
      });

      if (!res?.data) throw new NotFoundError('No data');

      const decrypted = await decryptVidnestData(res.data);
      const sources = decrypted.sources || decrypted.streams || [];

      const streams: string[] = [];
      for (const source of sources) {
        const url = source.file || source.url;
        if (!url) continue;
        if (config?.streamDomains && !config.streamDomains.some((d) => url.includes(d))) continue;
        streams.push(url);
      }

      if (!streams.length) throw new NotFoundError('No streams');

      ctx.progress(100);

      return {
        stream: [
          {
            id,
            type: 'hls',
            playlist: streams[0],
            headers: {
              Origin: config?.origin,
              Referer: config?.referer,
            },
            flags: [],
            captions: [],
          },
        ],
      };
    },
  });
}

export const VidnestEmbeds = VIDNEST_SERVERS.map((server, i) => makeVidnestEmbed(server, 104 - i));
