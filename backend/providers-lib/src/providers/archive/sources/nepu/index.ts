import { load } from 'cheerio';

import { SourcererOutput, makeSourcerer } from '@/providers/base';
import { compareMedia } from '@/utils/compare';
import { MovieScrapeContext, ShowScrapeContext } from '@/utils/context';
import { NotFoundError } from '@/utils/errors';

import { SearchResults } from './types';

const nepuBase = 'https://rar.to';
const nepuReferer = 'https://rar.to/';

const universalScraper = async (ctx: MovieScrapeContext | ShowScrapeContext) => {
  const searchResultRequest = await ctx.proxiedFetcher<string>('/ajax/posts', {
    baseUrl: nepuBase,
    query: {
      q: ctx.media.title,
    },
  });

  // json isn't parsed by proxiedFetcher due to content-type being text/html.
  const searchResult = JSON.parse(searchResultRequest) as SearchResults;

  const show = searchResult.data.find((item) => {
    if (!item) return false;
    if (ctx.media.type === 'movie' && item.type !== 'Movie') return false;
    if (ctx.media.type === 'show' && item.type !== 'Show') return false;

    const [, title, year] = item.name.match(/^(.*?)\s*(?:\(?\s*(\d{4})(?:\s*-\s*\d{0,4})?\s*\)?)?\s*$/) || [];
    return compareMedia(ctx.media, title, Number(year));
  });

  if (!show) throw new NotFoundError('No watchable item found');

  let videoUrl = show.url;

  if (ctx.media.type === 'show') {
    videoUrl = `${show.url}/season/${ctx.media.season.number}/episode/${ctx.media.episode.number}`;
  }
  ctx.progress(50);

  const videoPage = await ctx.proxiedFetcher<string>(videoUrl, {
    baseUrl: nepuBase,
  });
  const videoPage$ = load(videoPage);
  const embedId = videoPage$('a[data-embed]').attr('data-embed');

  if (!embedId) throw new NotFoundError('No embed found.');

  const playerPage = await ctx.proxiedFetcher<string>('/ajax/embed', {
    method: 'POST',
    baseUrl: nepuBase,
    body: new URLSearchParams({ id: embedId }),
  });

  const streamUrl = playerPage.match(/"file":"([^"]+)"/);

  if (!streamUrl?.[1]) throw new NotFoundError('No stream found.');
  ctx.progress(90);

  return {
    embeds: [],
    stream: [
      {
        id: 'primary',
        captions: [],
        playlist: nepuBase + streamUrl[1],
        type: 'hls',
        headers: {
          Origin: nepuBase,
          Referer: nepuReferer,
        },
        flags: [],
      },
    ],
  } as SourcererOutput;
};

export const nepuScraper = makeSourcerer({
  id: 'nepu',
  name: 'Nepu',
  rank: 210,
  disabled: true,
  flags: [],
  scrapeMovie: universalScraper,
  scrapeShow: universalScraper,
});
