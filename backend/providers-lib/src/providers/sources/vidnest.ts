import { SourcererOutput, makeSourcerer } from '@/providers/base';
import { MovieScrapeContext, ShowScrapeContext } from '@/utils/context';

async function comboScraper(ctx: ShowScrapeContext | MovieScrapeContext): Promise<SourcererOutput> {
  const query: Record<string, any> = {
    type: ctx.media.type,
    tmdbId: ctx.media.tmdbId,
  };

  if (ctx.media.type === 'show') {
    query.season = ctx.media.season.number;
    query.episode = ctx.media.episode.number;
  }

  return {
    embeds: [
      { embedId: 'vidnest-hollymoviehd', url: JSON.stringify(query) },
      { embedId: 'vidnest-allmovies', url: JSON.stringify(query) },
    ],
  };
}

export const vidnestScraper = makeSourcerer({
  id: 'vidnest',
  name: 'Vidnest',
  rank: 115,
  flags: [],
  disabled: true, // The streams cause the site to crash
  scrapeMovie: comboScraper,
  scrapeShow: comboScraper,
});
