import { flags } from '@/entrypoint/utils/targets';
import { SourcererOutput, makeSourcerer } from '@/providers/base';
import { MovieScrapeContext, ShowScrapeContext } from '@/utils/context';
import { NotFoundError } from '@/utils/errors';

const baseUrl = 'https://rover.rove.cx';

async function comboScraper(ctx: ShowScrapeContext | MovieScrapeContext): Promise<SourcererOutput> {
  const apiUrl =
    ctx.media.type === 'movie'
      ? `${baseUrl}/movie/${ctx.media.tmdbId}`
      : `${baseUrl}/tv/${ctx.media.tmdbId}/${ctx.media.season.number}/${ctx.media.episode.number}`;

  const apiRes = await ctx.proxiedFetcher(apiUrl);

  if (!apiRes.stream.hls) throw new NotFoundError('No watchable item found');
  ctx.progress(90);

  return {
    embeds: [],
    stream: [
      {
        id: 'primary',
        captions: [],
        playlist: apiRes.stream.hls,
        type: 'hls',
        flags: [flags.CORS_ALLOWED],
      },
    ],
  };
}

export const roverScraper = makeSourcerer({
  id: 'rover',
  name: 'Rover',
  rank: 189,
  disabled: true,
  flags: [flags.CORS_ALLOWED],
  scrapeMovie: comboScraper,
  scrapeShow: comboScraper,
});
