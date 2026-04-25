import { flags } from '@/entrypoint/utils/targets';
import { makeEmbed } from '@/providers/base';
import { createM3U8ProxyUrl } from '@/utils/proxy';

const embeds = [
  {
    id: 'vidsrc-comet',
    name: 'Comet',
    rank: 39,
  },
  {
    id: 'vidsrc-pulsar',
    name: 'Pulsar',
    rank: 38,
  },
  {
    id: 'vidsrc-nova',
    name: 'Nova',
    rank: 37,
  },
];

const headers = {
  referer: 'https://vidsrc.vip/',
  origin: 'https://vidsrc.vip',
};

function makeVidSrcEmbed(provider: { id: string; name: string; rank: number }) {
  return makeEmbed({
    id: provider.id,
    name: provider.name,
    rank: provider.rank,
    flags: [flags.CORS_ALLOWED],
    async scrape(ctx) {
      if (ctx.url.includes('https://cdn.niggaflix.xyz')) {
        return {
          stream: [
            {
              id: 'primary',
              type: 'hls',
              playlist: createM3U8ProxyUrl(ctx.url, ctx.features, headers),
              headers,
              flags: [flags.CORS_ALLOWED],
              captions: [],
            },
          ],
        };
      }

      return {
        stream: [
          {
            id: 'primary',
            type: 'hls',
            playlist: ctx.url,
            flags: [flags.CORS_ALLOWED],
            captions: [],
          },
        ],
      };
    },
  });
}

export const [vidsrcCometEmbed, vidsrcPulsarEmbed, vidsrcNovaEmbed] = embeds.map(makeVidSrcEmbed);
