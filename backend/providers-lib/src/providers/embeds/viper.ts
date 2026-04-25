import { flags } from '@/entrypoint/utils/targets';
import { makeEmbed } from '@/providers/base';
import { NotFoundError } from '@/utils/errors';
import { createM3U8ProxyUrl } from '@/utils/proxy';

export const viperScraper = makeEmbed({
  id: 'viper',
  name: 'Viper',
  rank: 182,
  disabled: true,
  flags: [flags.CORS_ALLOWED],
  async scrape(ctx) {
    const apiResponse = await ctx.proxiedFetcher.full<{
      source: string;
    }>(ctx.url, {
      headers: {
        Accept: 'application/json',
        Referer: 'https://embed.su/',
      },
    });

    if (!apiResponse.body.source) {
      throw new NotFoundError('No source found');
    }
    const playlistUrl = apiResponse.body.source.replace(/^.*\/viper\//, 'https://');

    // Headers needed for the M3U8 proxy
    const headers = {
      referer: 'https://megacloud.store/',
      origin: 'https://megacloud.store',
    };

    return {
      stream: [
        {
          type: 'hls',
          id: 'primary',
          playlist: createM3U8ProxyUrl(playlistUrl, ctx.features, headers),
          headers,
          flags: [flags.CORS_ALLOWED],
          captions: [],
        },
      ],
    };
  },
});
