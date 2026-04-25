import { flags } from '@/entrypoint/utils/targets';
import { SourcererOutput, makeSourcerer } from '@/providers/base';
import { compareTitle } from '@/utils/compare';
import { MovieScrapeContext, ShowScrapeContext } from '@/utils/context';
import { makeCookieHeader } from '@/utils/cookie';
import { NotFoundError } from '@/utils/errors';
import { createM3U8ProxyUrl } from '@/utils/proxy';

// thanks @TPN for this
// See how to set this up yourself: https://gist.github.com/Pasithea0/9ba31d16580800e899c245a4379e902b

const baseUrl = 'https://iosmirror.cc';
const baseUrl2 = 'https://vercel-sucks.up.railway.app/iosmirror.cc:443';

type metaT = {
  year: string;
  type: 'm' | 't';
  season: { s: string; id: string; ep: string }[];
};

type searchT = { status: 'y' | 'n'; searchResult?: { id: string; t: string }[]; error: string };

type episodeT = { episodes: { id: string; s: string; ep: string }[]; nextPageShow: number };

// const userAgent = navigator.userAgent.toLowerCase();
// const isIos = /iphone|ipad|ipod/.test(userAgent);

const universalScraper = async (ctx: ShowScrapeContext | MovieScrapeContext): Promise<SourcererOutput> => {
  const hash = decodeURIComponent(await ctx.fetcher('https://iosmirror-hash.pstream.org/'));
  if (!hash) throw new NotFoundError('No hash found');
  ctx.progress(10);

  const searchRes = await ctx.proxiedFetcher<searchT>('/search.php', {
    baseUrl: baseUrl2,
    query: { s: ctx.media.title },
    headers: { cookie: makeCookieHeader({ t_hash_t: hash, hd: 'on' }) },
  });
  if (searchRes.status !== 'y' || !searchRes.searchResult) throw new NotFoundError(searchRes.error);

  async function getMeta(id: string) {
    return ctx.proxiedFetcher<metaT>('/post.php', {
      baseUrl: baseUrl2,
      query: { id },
      headers: { cookie: makeCookieHeader({ t_hash_t: hash, hd: 'on' }) },
    });
  }
  ctx.progress(30);

  let metaRes: metaT | undefined;

  // todo: use promise.alp
  let id = searchRes.searchResult.find(async (x) => {
    metaRes = await getMeta(x.id);
    return (
      compareTitle(x.t, ctx.media.title) &&
      (Number(metaRes.year) === ctx.media.releaseYear || metaRes.type === (ctx.media.type === 'movie' ? 'm' : 't'))
    );
  })?.id;
  if (!id) throw new NotFoundError('No watchable item found');

  if (ctx.media.type === 'show') {
    metaRes = await getMeta(id); // shouldnt need this, idunno why it doesnt work without this
    const showMedia = ctx.media;

    const seasonId = metaRes?.season.find((x) => Number(x.s) === showMedia.season.number)?.id;
    if (!seasonId) throw new NotFoundError('Season not available');

    const episodeRes = await ctx.proxiedFetcher<episodeT>('/episodes.php', {
      baseUrl: baseUrl2,
      query: { s: seasonId, series: id },
      headers: { cookie: makeCookieHeader({ t_hash_t: hash, hd: 'on' }) },
    });

    let episodes = [...episodeRes.episodes];
    let currentPage = 2;
    while (episodeRes.nextPageShow === 1) {
      const nextPageRes = await ctx.proxiedFetcher<episodeT>('/episodes.php', {
        baseUrl: baseUrl2,
        query: { s: seasonId, series: id, page: currentPage.toString() },
        headers: { cookie: makeCookieHeader({ t_hash_t: hash, hd: 'on' }) },
      });

      episodes = [...episodes, ...nextPageRes.episodes];
      episodeRes.nextPageShow = nextPageRes.nextPageShow;
      currentPage++;
    }

    const episodeId = episodes.find(
      (x) => x.ep === `E${showMedia.episode.number}` && x.s === `S${showMedia.season.number}`,
    )?.id;
    if (!episodeId) throw new NotFoundError('Episode not available');

    id = episodeId;
  }

  const playlistRes: { sources: { file: string; label: string }[] }[] = await ctx.proxiedFetcher('/playlist.php?', {
    baseUrl: baseUrl2,
    query: { id },
    headers: { cookie: makeCookieHeader({ t_hash_t: hash, hd: 'on' }) },
  });
  ctx.progress(50);

  let autoFile = playlistRes[0].sources.find((source) => source.label === 'Auto')?.file;
  if (!autoFile) {
    autoFile = playlistRes[0].sources.find((source) => source.label === 'Full HD')?.file;
  }
  if (!autoFile) {
    // eslint-disable-next-line no-console
    console.log('"Full HD" or "Auto" file not found, falling back to first source');
    autoFile = playlistRes[0].sources[0].file;
  }

  if (!autoFile) throw new Error('Failed to fetch playlist');

  const headers = {
    referer: baseUrl,
    cookie: makeCookieHeader({ hd: 'on' }),
  };

  const playlist = createM3U8ProxyUrl(`${baseUrl}${autoFile}`, ctx.features, headers);
  ctx.progress(90);

  return {
    embeds: [],
    stream: [
      {
        id: 'primary',
        playlist,
        type: 'hls',
        headers,
        flags: [flags.CORS_ALLOWED],
        captions: [],
      },
    ],
  };
};

export const iosmirrorScraper = makeSourcerer({
  id: 'iosmirror',
  name: 'NetMirror',
  rank: 182,
  // disabled: !!isIos,
  disabled: true,
  flags: [flags.CORS_ALLOWED],
  scrapeMovie: universalScraper,
  scrapeShow: universalScraper,
});
