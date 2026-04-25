import { flags } from '@/entrypoint/utils/targets';
import { SourcererEmbed, SourcererOutput, makeSourcerer } from '@/providers/base';
import { MovieScrapeContext, ShowScrapeContext } from '@/utils/context';
import { NotFoundError } from '@/utils/errors';

const BASE = 'https://www.2embed.cc';

/**
 * 2embed iframe URLs + optional future api.2embed.cc wiring.
 * TV uses `?s=&e=` (the operator table used `&` after the id; query form is valid HTML).
 * @see backend/providers-api/docs/CUSTOM_EMBED_INTEGRATION.md §2
 */
function buildMovieEmbedUrl(ctx: MovieScrapeContext): string {
  const { tmdbId, imdbId } = ctx.media;
  if (imdbId && imdbId.startsWith('tt')) {
    return `${BASE}/embed/${encodeURI(imdbId)}`;
  }
  if (tmdbId) {
    return `${BASE}/embed/${encodeURI(String(tmdbId))}`;
  }
  throw new NotFoundError('Missing tmdbId/imdbId for 2embed movie');
}

function buildShowEmbedUrl(ctx: ShowScrapeContext): string {
  const { tmdbId, imdbId } = ctx.media;
  const s = ctx.media.season.number;
  const e = ctx.media.episode.number;
  const id = imdbId && imdbId.startsWith('tt') ? imdbId : tmdbId;
  if (!id) {
    throw new NotFoundError('Missing tmdbId/imdbId for 2embed TV');
  }
  return `${BASE}/embedtv/${encodeURI(String(id))}?s=${s}&e=${e}`;
}

async function comboScraper(ctx: ShowScrapeContext | MovieScrapeContext): Promise<SourcererOutput> {
  ctx.progress(20);

  const url =
    ctx.media.type === 'show'
      ? buildShowEmbedUrl(ctx as ShowScrapeContext)
      : buildMovieEmbedUrl(ctx as MovieScrapeContext);

  ctx.progress(50);

  const embeds: SourcererEmbed[] = [
    {
      embedId: 'twoembed-iframe',
      url,
    },
  ];

  ctx.progress(90);
  return { embeds };
}

export const twoembedScraper = makeSourcerer({
  id: 'twoembed',
  name: '2embed.cc',
  rank: 307,
  disabled: false,
  flags: [flags.CORS_ALLOWED],
  scrapeMovie: comboScraper,
  scrapeShow: comboScraper,
});
