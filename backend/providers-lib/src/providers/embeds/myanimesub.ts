import { flags } from '@/entrypoint/utils/targets';
import { makeEmbed } from '@/providers/base';
import { Caption, getCaptionTypeFromUrl, labelToLanguageCode } from '@/providers/captions';
import { NotFoundError } from '@/utils/errors';
import { createM3U8ProxyUrl } from '@/utils/proxy';

export const myanimesubScraper = makeEmbed({
  id: 'myanimesub',
  name: 'MyAnime (Sub)',
  rank: 204,
  flags: [flags.CORS_ALLOWED],
  async scrape(ctx) {
    const streamData = await ctx.proxiedFetcher<any>(
      `https://anime.aether.mom/api/stream?id=${ctx.url}&server=HD-2&type=sub`,
    );

    if (!streamData.results.streamingLink?.link?.file) {
      throw new NotFoundError('No watchable sources found');
    }

    const getValidTimestamp = (timestamp: any) => {
      if (!timestamp || typeof timestamp !== 'object') return null;
      const start = parseInt(timestamp.start, 10);
      const end = parseInt(timestamp.end, 10);
      if (Number.isNaN(start) || Number.isNaN(end) || start <= 0 || end <= 0 || start >= end) return null;
      return { start, end };
    };

    const intro = getValidTimestamp(streamData.results.streamingLink.intro);
    const outro = getValidTimestamp(streamData.results.streamingLink.outro);

    return {
      stream: [
        {
          id: 'sub',
          type: 'hls',
          playlist: createM3U8ProxyUrl(streamData.results.streamingLink.link.file, ctx.features, {
            Referer: 'https://rapid-cloud.co/',
          }),
          headers: {
            Referer: 'https://rapid-cloud.co/',
          },
          flags: [flags.CORS_ALLOWED],
          captions:
            (streamData.results.streamingLink.tracks
              ?.map((track: any) => {
                const lang = labelToLanguageCode(track.label);
                const type = getCaptionTypeFromUrl(track.file);
                if (!lang || !type) return null;
                return {
                  id: track.file,
                  url: track.file,
                  language: lang,
                  type,
                  hasCorsRestrictions: true,
                };
              })
              .filter((x: any) => x) as Caption[]) ?? [],
          intro,
          outro,
        },
      ],
    };
  },
});
