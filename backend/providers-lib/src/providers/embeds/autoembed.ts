import { flags } from '@/entrypoint/utils/targets';
import { makeEmbed } from '@/providers/base';

const providers = [
  {
    id: 'autoembed-english',
    rank: 10,
  },
  {
    id: 'autoembed-hindi',
    rank: 9,
    disabled: true,
  },
  {
    id: 'autoembed-tamil',
    rank: 8,
    disabled: true,
  },
  {
    id: 'autoembed-telugu',
    rank: 7,
    disabled: true,
  },
  {
    id: 'autoembed-bengali',
    rank: 6,
    disabled: true,
  },
];

function embed(provider: { id: string; rank: number; disabled?: boolean }) {
  return makeEmbed({
    id: provider.id,
    name: provider.id
      .split('-')
      .map((word) => word[0].toUpperCase() + word.slice(1))
      .join(' '),
    disabled: provider.disabled,
    rank: provider.rank,
    flags: [flags.CORS_ALLOWED],
    async scrape(ctx) {
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

export const [
  autoembedEnglishScraper,
  autoembedHindiScraper,
  autoembedBengaliScraper,
  autoembedTamilScraper,
  autoembedTeluguScraper,
] = providers.map(embed);
