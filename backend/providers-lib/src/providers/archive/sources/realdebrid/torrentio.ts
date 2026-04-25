/* eslint-disable no-console */
import { MovieScrapeContext, ShowScrapeContext } from '@/utils/context';
import { NotFoundError } from '@/utils/errors';

interface TorrentStream {
  name: string;
  title: string;
  url: string;
  infoHash?: string;
  sources?: string[];
  behaviorHints?: {
    bingeGroup?: string;
    countryWhitelist?: string[];
    filename?: string;
  };
}

export interface QualityTorrents {
  [quality: string]: string;
}

// Filter out cam/ts/screener versions
function isAcceptableQuality(torrentName: string): boolean {
  const lowerName = torrentName.toLowerCase();
  const bannedTerms = [
    'cam',
    'camrip',
    'hdcam',
    'ts',
    'telesync',
    'hdts',
    'dvdscr',
    'screener',
    'scr',
    'r5',
    'workprint',
  ];

  return !bannedTerms.some((term) => lowerName.includes(term));
}

// Extract quality from torrent name
function extractQuality(torrentName: string): string {
  const name = torrentName.toLowerCase();

  if (name.includes('2160p') || name.includes('4k')) return '4K';
  if (name.includes('1080p')) return '1080P';
  if (name.includes('720p')) return '720P';
  if (name.includes('480p')) return '480P';
  if (name.includes('360p')) return '360P';

  return 'unknown';
}

// Process torrents and group by quality
function processTorrents(streams: TorrentStream[]): QualityTorrents {
  // Filter out bad quality torrents
  const goodQualityStreams = streams.filter((stream) => isAcceptableQuality(stream.name));
  const filteredStreams = goodQualityStreams.filter(
    (stream) =>
      stream.title?.toLowerCase().includes('mp4') || stream.behaviorHints?.filename?.toLowerCase().includes('mp4'),
  );

  if (filteredStreams.length === 0) {
    throw new NotFoundError('No usable torrents found');
  }

  // if (filteredStreams.length > 0) {
  //   console.log('sample stream:', JSON.stringify(filteredStreams[0], null, 2)); // eslint-disable-line no-console
  // }

  // Group torrents by quality
  const qualityGroups: { [quality: string]: TorrentStream[] } = {};

  for (const stream of filteredStreams) {
    const quality = extractQuality(stream.name);
    if (!qualityGroups[quality]) {
      qualityGroups[quality] = [];
    }
    qualityGroups[quality].push(stream);
  }

  // Select the best torrent for each quality (we just pick the first one)
  const result: QualityTorrents = {};

  for (const [quality, torrentStreams] of Object.entries(qualityGroups)) {
    if (torrentStreams.length > 0) {
      // Check if the URL is a magnet link, if not create one using infoHash if available
      const stream = torrentStreams[0];
      let magnetUrl = stream.url;

      if (!magnetUrl && stream.infoHash) {
        // Create a magnet link from the infoHash
        magnetUrl = `magnet:?xt=urn:btih:${stream.infoHash}&dn=${encodeURIComponent(stream.name)}`;
      }

      if (magnetUrl) {
        result[quality] = magnetUrl;
      }
    }
  }

  console.log('processed qualities:', Object.keys(result));
  for (const [quality, url] of Object.entries(result)) {
    console.log(`${quality}: ${url.substring(0, 30)}...`);
  }

  return result;
}

// Function to get torrents from Torrentio service
export async function getTorrents(ctx: MovieScrapeContext | ShowScrapeContext): Promise<QualityTorrents> {
  if (!ctx.media.imdbId) {
    throw new NotFoundError('IMDB ID required');
  }

  const imdbId = ctx.media.imdbId;
  let searchPath: string;

  if (ctx.media.type === 'show') {
    const seasonNumber = ctx.media.season.number;
    const episodeNumber = ctx.media.episode.number;
    searchPath = `series/${imdbId}:${seasonNumber}:${episodeNumber}.json`;
  } else {
    searchPath = `movie/${imdbId}.json`;
  }

  try {
    const torrentioUrl = `https://torrentio.strem.fun/providers=yts,eztv,rarbg,1337x,thepiratebay,kickasstorrents,torrentgalaxy,magnetdl/stream/${searchPath}`;
    console.log('Fetching torrents from:', torrentioUrl);

    const response = await ctx.fetcher.full(torrentioUrl);

    if (response.statusCode !== 200) {
      throw new NotFoundError(`Failed to fetch torrents: ${response.statusCode} ${response.body}`);
    }

    console.log('Found torrents:', response.body.streams?.length || 0);

    if (!response.body.streams || response.body.streams.length === 0) {
      throw new NotFoundError('No streams found');
    }

    // Process and group torrents by quality
    return processTorrents(response.body.streams);
  } catch (error: unknown) {
    if (error instanceof NotFoundError) throw error;
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';
    throw new NotFoundError(`Error fetching torrents: ${errorMessage}`);
  }
}
