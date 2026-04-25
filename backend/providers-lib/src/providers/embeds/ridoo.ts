import { flags } from '@/entrypoint/utils/targets';
import { NotFoundError } from '@/utils/errors';

import { makeEmbed } from '../base';

const referer = 'https://ridomovies.tv/';

const playlistHeaders = {
  referer: 'https://ridoo.net/',
  origin: 'https://ridoo.net',
};

export const ridooScraper = makeEmbed({
  id: 'ridoo',
  name: 'Ridoo',
  rank: 121,
  flags: [flags.CORS_ALLOWED],
  async scrape(ctx) {
    const res = await ctx.proxiedFetcher<string>(ctx.url, {
      headers: {
        referer,
      },
    });
    const regexPattern = /file:"([^"]+)"/g;
    const url = regexPattern.exec(res)?.[1];
    if (!url) throw new NotFoundError('Unable to find source url');

    return {
      stream: [
        {
          id: 'primary',
          type: 'hls',
          playlist: url,
          headers: playlistHeaders,
          captions: [],
          flags: [flags.CORS_ALLOWED],
        },
      ],
    };
  },
});
