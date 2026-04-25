// Helpers for Stremio addon API Formats

import { MovieScrapeContext, ShowScrapeContext } from '@/utils/context';

import { DebridParsedStream, stremioStream } from './types';

export async function getAddonStreams(
  addonUrl: string,
  ctx: MovieScrapeContext | ShowScrapeContext,
): Promise<{ streams: stremioStream[] }> {
  if (!ctx.media.imdbId) {
    throw new Error('Error: ctx.media.imdbId is required.');
  }
  let addonResponse: { streams: stremioStream[] } | undefined;

  if (ctx.media.type === 'show') {
    addonResponse = await ctx.proxiedFetcher(
      `${addonUrl}/stream/series/${ctx.media.imdbId}:${ctx.media.season.number}:${ctx.media.episode.number}.json`,
    );
  } else {
    addonResponse = await ctx.proxiedFetcher(`${addonUrl}/stream/movie/${ctx.media.imdbId}.json`);
  }

  if (!addonResponse) {
    throw new Error('Error: addon did not respond');
  }

  return addonResponse;
}

interface StreamInput {
  title: string;
  url: string;
  [key: string]: any;
}

export async function parseStreamData(
  streams: StreamInput[],
  ctx: MovieScrapeContext | ShowScrapeContext,
): Promise<DebridParsedStream[]> {
  return ctx.proxiedFetcher('https://torrent-parse.pstream.mov', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(streams),
  });
}
