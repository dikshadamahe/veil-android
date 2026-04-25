/* eslint-disable no-console */
import { flags } from '@/entrypoint/utils/targets';
import { SourcererOutput, makeSourcerer } from '@/providers/base';
import { MovieScrapeContext, ShowScrapeContext } from '@/utils/context';
import { NotFoundError } from '@/utils/errors';

import { getUnrestrictedLink } from './debrid';
import { getTorrents } from './torrentio';

const OVERRIDE_TOKEN = '';

const getRealDebridToken = (): string | null => {
  try {
    if (OVERRIDE_TOKEN) return OVERRIDE_TOKEN;
  } catch {
    // Ignore
  }
  try {
    if (typeof window === 'undefined') return null;
    const prefData = window.localStorage.getItem('__MW::preferences');
    if (!prefData) return null;
    const parsedAuth = JSON.parse(prefData);
    return parsedAuth?.state?.realDebridKey || null;
  } catch (e) {
    console.error('Error getting RealDebrid token:', e);
    return null;
  }
};

async function comboScraper(ctx: ShowScrapeContext | MovieScrapeContext): Promise<SourcererOutput> {
  const apiToken = getRealDebridToken();
  if (!apiToken) {
    throw new NotFoundError('RealDebrid API token is required');
  }
  if (!ctx.media.imdbId) {
    throw new NotFoundError('IMDB ID required');
  }

  // Get torrent magnet links from Torrentio
  const streams = await getTorrents(ctx);
  // console.log('streams', streams);

  ctx.progress(20);

  // Process each magnet link through RealDebrid in batches
  const maxConcurrentQualities = 2;
  const qualities = Object.keys(streams);
  const processedStreams: Array<{ quality: string; url: string } | null> = [];

  // Process qualities in batches to avoid too many concurrent requests
  for (let i = 0; i < qualities.length; i += maxConcurrentQualities) {
    const batch = qualities.slice(i, i + maxConcurrentQualities);
    // progress
    const progressStart = 40;
    const progressEnd = 90;
    const progressPerBatch = (progressEnd - progressStart) / Math.ceil(qualities.length / maxConcurrentQualities);
    const currentBatchProgress = progressStart + progressPerBatch * (i / maxConcurrentQualities);
    ctx.progress(Math.round(currentBatchProgress));

    const batchPromises = batch.map((quality) => {
      const magnetUrl = streams[quality];
      return getUnrestrictedLink(magnetUrl, apiToken, ctx)
        .then((downloadUrl) => ({ quality, url: downloadUrl }))
        .catch((error) => {
          console.error(`Failed to process ${quality} stream:`, error);
          return null;
        });
    });

    if (batchPromises.length > 0) {
      const batchResults = await Promise.all(batchPromises);
      processedStreams.push(...batchResults);
    }
  }

  // Filter out failed streams and create quality map
  const filteredStreams = processedStreams
    .filter((stream): stream is { quality: string; url: string } => stream !== null)
    .filter((stream) => stream.url.toLowerCase().endsWith('.mp4')) // only mp4
    .reduce((acc: Record<string, string>, { quality, url }) => {
      // Normalize quality format for the output
      let qualityKey: number | string;
      if (quality === '4K') {
        qualityKey = 2160;
      } else {
        qualityKey = parseInt(quality.replace('P', ''), 10);
      }
      if (Number.isNaN(qualityKey)) qualityKey = 'unknown';

      acc[qualityKey] = url;
      return acc;
    }, {});

  if (Object.keys(filteredStreams).length === 0) {
    throw new NotFoundError('No suitable streams found');
  }

  ctx.progress(100);

  return {
    stream: [
      {
        id: 'primary',
        captions: [],
        qualities: {
          ...(filteredStreams[2160] && {
            '4k': {
              type: 'mp4',
              url: filteredStreams[2160],
            },
          }),
          ...(filteredStreams[1080] && {
            1080: {
              type: 'mp4',
              url: filteredStreams[1080],
            },
          }),
          ...(filteredStreams[720] && {
            720: {
              type: 'mp4',
              url: filteredStreams[720],
            },
          }),
          ...(filteredStreams[480] && {
            480: {
              type: 'mp4',
              url: filteredStreams[480],
            },
          }),
          ...(filteredStreams[360] && {
            360: {
              type: 'mp4',
              url: filteredStreams[360],
            },
          }),
          ...(filteredStreams.unknown && {
            unknown: {
              type: 'mp4',
              url: filteredStreams.unknown,
            },
          }),
        },
        type: 'file',
        flags: [flags.CORS_ALLOWED],
      },
    ],
    embeds: [],
  };
}

export const realDebridScraper = makeSourcerer({
  id: 'realdebrid',
  name: 'RealDebrid (Beta)',
  rank: 280,
  disabled: !getRealDebridToken(),
  flags: [flags.CORS_ALLOWED],
  scrapeMovie: comboScraper,
  scrapeShow: comboScraper,
});
