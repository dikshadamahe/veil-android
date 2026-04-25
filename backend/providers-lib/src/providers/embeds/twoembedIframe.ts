import { flags } from '@/entrypoint/utils/targets';
import { makeEmbed } from '@/providers/base';
import { pullM3U8FromEmbedPage } from '@/providers/utils/m3u8FromEmbedPage';
import { createM3U8ProxyUrl } from '@/utils/proxy';

const REF = 'https://www.2embed.cc/';

const UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

/**
 * Resolves a 2embed.cc embed page to HLS. api.2embed.cc can be added later for direct JSON.
 * @see backend/providers-api/docs/CUSTOM_EMBED_INTEGRATION.md §2
 */
export const twoembedIframe = makeEmbed({
  id: 'twoembed-iframe',
  name: '2embed.cc (iframe → m3u8)',
  rank: 329,
  disabled: false,
  flags: [flags.CORS_ALLOWED],
  async scrape(ctx) {
    const playlist = await pullM3u8FromEmbedPage({
      proxiedFetcher: ctx.proxiedFetcher,
      pageUrl: ctx.url,
      referer: REF,
      userAgent: UA,
    });

    const headers: Record<string, string> = {
      referer: 'https://www.2embed.cc/',
      origin: 'https://www.2embed.cc',
    };

    return {
      stream: [
        {
          type: 'hls',
          id: 'primary',
          playlist: createM3U8ProxyUrl(playlist, ctx.features, headers),
          flags: [flags.CORS_ALLOWED],
          captions: [],
          headers,
        },
      ],
    };
  },
});
