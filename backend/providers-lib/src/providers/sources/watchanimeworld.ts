import { load } from 'cheerio';

import { flags } from '@/entrypoint/utils/targets';
import { SourcererOutput, makeSourcerer } from '@/providers/base';
import { MovieScrapeContext, ShowScrapeContext } from '@/utils/context';
import { NotFoundError } from '@/utils/errors';

const baseUrl = 'https://watchanimeworld.in';
const zephyrBaseUrl = 'https://play.zephyrflick.top';
const tmdbApiKey = '5b9790d9305dca8713b9a0afad42ea8d'; // Same key used in hianime

interface TMDBShowResponse {
  name: string;
  original_name: string;
}

interface TMDBMovieResponse {
  title: string;
  original_title: string;
}

interface ZephyrStreamResponse {
  hls: boolean;
  videoSource: string;
  securedLink: string;
}

async function fetchTMDBData(tmdbId: string | number, mediaType: 'movie' | 'tv'): Promise<string> {
  const endpoint = mediaType === 'movie' ? 'movie' : 'tv';
  const response = await fetch(`https://api.themoviedb.org/3/${endpoint}/${tmdbId}?api_key=${tmdbApiKey}`);

  if (!response.ok) {
    throw new NotFoundError('Failed to fetch TMDB data');
  }

  const data = await response.json();

  // Return the English title, falling back to original title
  if (mediaType === 'movie') {
    const movieData = data as TMDBMovieResponse;
    return movieData.title || movieData.original_title;
  }
  const showData = data as TMDBShowResponse;
  return showData.name || showData.original_name;
}

function normalizeTitle(title: string): string {
  return title
    .toLowerCase()
    .normalize('NFD') // Decompose unicode characters
    .replace(/[\u0300-\u036f]/g, '') // Remove diacritics
    .replace(/[^a-z0-9\s-]/g, '') // Remove special characters except spaces and hyphens
    .replace(/\s+/g, '-') // Replace spaces with hyphens
    .replace(/-+/g, '-') // Replace multiple hyphens with single hyphen
    .trim();
}

async function comboScraper(ctx: ShowScrapeContext | MovieScrapeContext): Promise<SourcererOutput> {
  // Determine if this is a TV show based on context
  const isTVShow = 'season' in ctx.media;
  const endpoint = isTVShow ? 'tv' : 'movie';

  // Get the title from TMDB
  const title = await fetchTMDBData(ctx.media.tmdbId, endpoint);
  const normalizedTitle = normalizeTitle(title);

  // Build the watchanimeworld URL
  let watchUrl: string;
  if (ctx.media.type === 'movie') {
    watchUrl = `${baseUrl}/movies/${normalizedTitle}/`;
  } else {
    const season = ctx.media.season.number;
    const episode = ctx.media.episode.number;
    watchUrl = `${baseUrl}/episode/${normalizedTitle}-${season}x${episode}/`;
  }

  ctx.progress(30);

  // Fetch the watch page

  const watchPage = await ctx.proxiedFetcher(watchUrl, {
    headers: {
      'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
    },
  });

  // Extract iframe src
  const $ = load(watchPage);
  const iframeSrc = $('iframe[data-src]').attr('data-src') || $('iframe[src]').attr('src');

  if (!iframeSrc) {
    throw new NotFoundError('No iframe found on watch page');
  }

  // Extract the hash from the iframe URL
  const hashMatch = iframeSrc.match(/\/video\/([a-f0-9]+)/);
  if (!hashMatch) {
    throw new NotFoundError('Could not extract video hash from iframe');
  }

  const videoHash = hashMatch[1];
  ctx.progress(60);

  // Construct the zephyrflick API URL
  const apiUrl = `${zephyrBaseUrl}/player/index.php?data=${videoHash}&do=getVideo`;

  // Fetch stream data
  const streamResponse = await ctx.proxiedFetcher(apiUrl, {
    method: 'POST',
    headers: {
      'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
      Referer: `${zephyrBaseUrl}/`,
      Origin: zephyrBaseUrl,
      Accept: 'application/json, text/plain, */*',
      'Content-Type': 'application/x-www-form-urlencoded',
      'X-Requested-With': 'XMLHttpRequest',
    },
    body: `data=${videoHash}&do=getVideo`,
  });

  const streamData: ZephyrStreamResponse = JSON.parse(streamResponse);

  if (!streamData.hls || !streamData.videoSource) {
    throw new NotFoundError('No HLS stream found');
  }

  ctx.progress(90);

  const streamHeaders = {
    Referer: `${zephyrBaseUrl}/`,
    Origin: zephyrBaseUrl,
    'User-Agent':
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
  };

  // Return the stream
  return {
    embeds: [],
    stream: [
      {
        id: 'primary',
        type: 'hls',
        playlist: streamData.videoSource,
        headers: streamHeaders,
        flags: [flags.CORS_ALLOWED],
        captions: [],
      },
    ],
  };
}

export const watchanimeworldScraper = makeSourcerer({
  id: 'watchanimeworld',
  name: 'WatchAnimeWorld',
  rank: 116,
  disabled: false,
  flags: [],
  scrapeMovie: comboScraper,
  scrapeShow: comboScraper,
});
