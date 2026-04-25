import { flags } from '@/entrypoint/utils/targets';
import { makeEmbed } from '@/providers/base';

const providers = [
  {
    id: 'streamtape',
    name: 'Streamtape',
    rank: 160,
  },
  {
    id: 'streamtape-latino',
    name: 'Streamtape (Latino)',
    rank: 159,
  },
];

function embed(provider: { id: string; name: string; rank: number }) {
  return makeEmbed({
    id: provider.id,
    name: provider.name,
    rank: provider.rank,
    flags: [flags.CORS_ALLOWED], // No longer IP locked
    async scrape(ctx) {
      const embedHtml = await ctx.proxiedFetcher<string>(ctx.url);

      const match = embedHtml.match(/robotlink'\).innerHTML = (.*)'/);
      if (!match) throw new Error('No match found');

      const [fh, sh] = match?.[1]?.split("+ ('") ?? [];
      if (!fh || !sh) throw new Error('No match found');

      const url = `https:${fh?.replace(/'/g, '').trim()}${sh?.substring(3).trim()}`;

      return {
        stream: [
          {
            id: 'primary',
            type: 'file',
            flags: [flags.CORS_ALLOWED], // No longer IP locked
            captions: [],
            qualities: {
              unknown: {
                type: 'mp4',
                url,
              },
            },
            preferredHeaders: {
              Referer: 'https://streamtape.com',
            },
          },
        ],
      };
    },
  });
}

export const [streamtapeScraper, streamtapeLatinoScraper] = providers.map(embed);
