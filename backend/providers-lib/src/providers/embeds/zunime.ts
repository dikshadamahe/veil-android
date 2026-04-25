import { flags } from '@/entrypoint/utils/targets';
import { NotFoundError } from '@/utils/errors';

import { EmbedOutput, makeEmbed } from '../base';

const ZUNIME_SERVERS = ['hd-2', 'miko', 'shiro', 'zaza'];

const baseUrl = 'https://backend.xaiby.sbs';
const headers = {
  referer: 'https://vidnest.fun/',
  origin: 'https://vidnest.fun',
  'User-Agent':
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
};

export function makeZunimeEmbed(id: string, rank: number = 100) {
  return makeEmbed({
    id: `zunime-${id}`,
    name: `Zunime ${id.charAt(0).toUpperCase() + id.slice(1)}`,
    rank,
    flags: [flags.CORS_ALLOWED],
    async scrape(ctx): Promise<EmbedOutput> {
      const serverName = id as (typeof ZUNIME_SERVERS)[number];

      const query = JSON.parse(ctx.url);
      const { anilistId, episode } = query;

      const res = await ctx.proxiedFetcher(`${'/sources'}`, {
        baseUrl,
        headers,
        query: {
          id: String(anilistId),
          ep: String(episode ?? 1),
          host: serverName,
          type: 'dub',
        },
      });

      // eslint-disable-next-line no-console
      console.log(res);

      const resAny: any = res as any;

      if (!resAny?.success || !resAny?.sources?.url) {
        throw new NotFoundError('No stream URL found in response');
      }

      const streamUrl = resAny.sources.url;
      const upstreamHeaders: Record<string, string> =
        resAny?.sources?.headers && Object.keys(resAny.sources.headers).length > 0 ? resAny.sources.headers : headers;

      ctx.progress(100);

      return {
        stream: [
          {
            id: 'primary',
            type: 'hls',
            playlist: `https://proxy-2.madaraverse.online/proxy?url=${encodeURIComponent(streamUrl)}`,
            headers: upstreamHeaders,
            flags: [],
            captions: [],
          },
        ],
      };
    },
  });
}

export const zunimeEmbeds = ZUNIME_SERVERS.map((server, i) => makeZunimeEmbed(server, 260 - i));
