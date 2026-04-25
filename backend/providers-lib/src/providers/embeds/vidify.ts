/* eslint-disable no-console */
import { NotFoundError } from '@/utils/errors';
import { createM3U8ProxyUrl } from '@/utils/proxy';

import { EmbedOutput, makeEmbed } from '../base';

const VIDIFY_SERVERS = ['alfa', 'bravo', 'charlie', 'delta', 'echo', 'foxtrot', 'golf', 'hotel', 'india', 'juliett'];

const baseUrl = 'api.vidify.top';

const playerUrl = 'https://player.vidify.top/';

let cachedAuthHeader: string | null = null;
let lastFetched: number = 0;

async function getAuthHeader(ctx: any): Promise<string> {
  const now = Date.now();
  // Cache for 1 hour
  if (cachedAuthHeader && now - lastFetched < 1000 * 60 * 60) {
    return cachedAuthHeader;
  }

  const playerPage = await ctx.proxiedFetcher(playerUrl, {
    headers: {
      Referer: playerUrl,
    },
  });

  const jsFileRegex = /\/assets\/index-([a-zA-Z0-9-]+)\.js/;
  const jsFileMatch = playerPage.match(jsFileRegex);
  if (!jsFileMatch) {
    throw new Error('Could not find the JS file URL in the player page');
  }
  const jsFileUrl = new URL(jsFileMatch[0], playerUrl).href;

  const jsContent = await ctx.proxiedFetcher(jsFileUrl, {
    headers: {
      Referer: playerUrl,
    },
  });

  const authRegex = /Authorization:"Bearer\s*([^"]+)"/;
  const authMatch = jsContent.match(authRegex);
  if (!authMatch || !authMatch[1]) {
    throw new Error('Could not extract the authorization header from the JS file');
  }

  cachedAuthHeader = `Bearer ${authMatch[1]}`;
  lastFetched = now;

  return cachedAuthHeader;
}

export function makeVidifyEmbed(id: string, rank: number = 100) {
  const serverIndex = VIDIFY_SERVERS.indexOf(id) + 1;

  return makeEmbed({
    id: `vidify-${id}`,
    name: `${id.charAt(0).toUpperCase() + id.slice(1)}`,
    rank,
    disabled: true,
    flags: [],
    async scrape(ctx): Promise<EmbedOutput> {
      const query = JSON.parse(ctx.url);
      const { type, tmdbId, season, episode } = query;

      let url = `https://${baseUrl}/`;

      if (type === 'movie') {
        url += `/movie/${tmdbId}?sr=${serverIndex}`;
      } else if (type === 'show') {
        url += `/tv/${tmdbId}/season/${season}/episode/${episode}?sr=${serverIndex}`;
      } else {
        throw new NotFoundError('Unsupported media type');
      }

      const authHeader = await getAuthHeader(ctx);
      const headers = {
        referer: 'https://player.vidify.top/',
        origin: 'https://player.vidify.top',
        Authorization: authHeader,
        'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
      };

      const res = await ctx.proxiedFetcher(url, { headers });
      console.log(res);

      const playlistUrl: string | undefined = res.m3u8 ?? res.url;

      if (Array.isArray(res.result) && res.result.length > 0) {
        const qualities: Record<string, { type: 'mp4'; url: string }> = {};
        res.result.forEach((r: { url: string | string[]; resolution: any }) => {
          if (r.url.includes('.mp4')) {
            qualities[`${r.resolution}p`] = { type: 'mp4', url: decodeURIComponent(r.url as string) };
          }
        });

        if (Object.keys(qualities).length === 0) {
          throw new NotFoundError('No MP4 streams found');
        }

        console.log(`Found MP4 streams: `, qualities);

        return {
          stream: [
            {
              id: 'primary',
              type: 'file',
              qualities,
              flags: [],
              captions: [],
              headers: {
                Host: 'proxy-worker.himanshu464121.workers.dev', // seems to be their only mp4 proxy
              },
            },
          ],
        };
      }

      if (!playlistUrl) throw new NotFoundError('No playlist URL found');

      const streamHeaders: Record<string, string> = { ...headers };
      let playlist: string;

      if (playlistUrl.includes('proxyv1.vidify.top')) {
        console.log(`Found stream (proxyv1): `, playlistUrl, streamHeaders);
        streamHeaders.Host = 'proxyv1.vidify.top';
        playlist = decodeURIComponent(playlistUrl);
      } else if (playlistUrl.includes('proxyv2.vidify.top')) {
        console.log(`Found stream (proxyv2): `, playlistUrl, streamHeaders);
        streamHeaders.Host = 'proxyv2.vidify.top';
        playlist = decodeURIComponent(playlistUrl);
      } else {
        console.log(`Found normal stream: `, playlistUrl);
        playlist = createM3U8ProxyUrl(decodeURIComponent(playlistUrl), ctx.features, streamHeaders);
      }

      ctx.progress(100);

      return {
        stream: [
          {
            id: 'primary',
            type: 'hls',
            playlist,
            headers: streamHeaders,
            flags: [],
            captions: [],
          },
        ],
      };
    },
  });
}

export const vidifyEmbeds = VIDIFY_SERVERS.map((server, i) => makeVidifyEmbed(server, 230 - i));
