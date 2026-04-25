import { flags } from '@/entrypoint/utils/targets';
import { SourcererEmbed, SourcererOutput, makeSourcerer } from '@/providers/base';
import { MovieScrapeContext, ShowScrapeContext } from '@/utils/context';
import { NotFoundError } from '@/utils/errors';

const BASE = 'https://vidsrc-embed.ru';

/**
 * Iframe embed pages per operator spec. Prefer TMDB when `tmdbId` is present.
 * @see backend/providers-api/docs/CUSTOM_EMBED_INTEGRATION.md §1
 */
function buildMovieEmbedUrl(ctx: MovieScrapeContext): string {
  const { tmdbId, imdbId } = ctx.media;
  if (imdbId && imdbId.startsWith('tt')) {
    return `${BASE}/embed/movie/${encodeURI(imdbId)}`;
  }
  if (tmdbId) {
    return `${BASE}/embed/movie/${encodeURI(String(tmdbId))}`;
  }
  throw new NotFoundError('Missing tmdbId/imdbId for vidsrcembed movie');
}

function buildShowEmbedUrl(ctx: ShowScrapeContext): string {
  const { tmdbId, imdbId } = ctx.media;
  const s = ctx.media.season.number;
  const e = ctx.media.episode.number;
  if (imdbId && imdbId.startsWith('tt')) {
    return `${BASE}/embed/tv/${encodeURI(imdbId)}/${s}-${e}`;
  }
  if (tmdbId) {
    return `${BASE}/embed/tv/${encodeURI(String(tmdbId))}/${s}-${e}`;
  }
  throw new NotFoundError('Missing tmdbId/imdbId for vidsrcembed TV');
}

async function comboScraper(ctx: ShowScrapeContext | MovieScrapeContext): Promise<SourcererOutput> {
  ctx.progress(20);

  const url =
    ctx.media.type === 'show' ? buildShowEmbedUrl(ctx as ShowScrapeContext) : buildMovieEmbedUrl(ctx as MovieScrapeContext);

  ctx.progress(50);

  const embeds: SourcererEmbed[] = [
    {
      embedId: 'vidsrcembed-iframe',
      url,
    },
  ];

  ctx.progress(90);
  return { embeds };
}

export const vidsrcembedScraper = makeSourcerer({
  id: 'vidsrcembed',
  name: 'VidSrc embed (vidsrc-embed.ru)',
  rank: 308,
  disabled: false,
  flags: [flags.CORS_ALLOWED],
  scrapeMovie: comboScraper,
  scrapeShow: comboScraper,
});
