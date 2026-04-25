import { MovieScrapeContext, ShowScrapeContext } from '@/utils/context';

const TMDB_API_KEY = 'a500049f3e06109fe3e8289b06cf5685';

export async function fetchTMDBName(
  ctx: ShowScrapeContext | MovieScrapeContext,
  lang: string = 'en-US',
): Promise<string> {
  const type = ctx.media.type === 'movie' ? 'movie' : 'tv';
  const url = `https://api.themoviedb.org/3/${type}/${ctx.media.tmdbId}?api_key=${TMDB_API_KEY}&language=${lang}`;

  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Error fetching TMDB data: ${response.statusText}`);
  }

  const data = await response.json();
  return ctx.media.type === 'movie' ? data.title : data.name;
}
