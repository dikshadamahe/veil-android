import { SourcererOutput, makeSourcerer } from '@/providers/base';
import { MovieScrapeContext, ShowScrapeContext } from '@/utils/context';
import { NotFoundError } from '@/utils/errors';

// Direct Vidsrc endpoints (vsembed.ru)
const VSEMBED_BASE = 'https://vsembed.ru/embed';

const headers = {
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36',
  Referer: 'https://vsembed.ru/',
  Origin: 'https://vsembed.ru',
};

async function comboScraper(ctx: MovieScrapeContext | ShowScrapeContext): Promise<SourcererOutput> {
  const { tmdbId } = ctx.media;

  ctx.progress(10);

  // Direct Vidsrc URL
  const embedUrl =
    ctx.media.type === 'movie'
      ? `${VSEMBED_BASE}/movie?tmdb=${tmdbId}`
      : `${VSEMBED_BASE}/tv?tmdb=${tmdbId}&season=${ctx.media.season.number}&episode=${ctx.media.episode.number}`;

  ctx.progress(30);

  const response = await ctx.proxiedFetcher<any>(embedUrl, {
    headers,
  });

  ctx.progress(60);

  if (!response) {
    throw new NotFoundError('No response from vidsrc');
  }

  // Extract stream data from vsembed response
  // vsembed returns an iframe with src or direct stream links
  let playlist: string | undefined;
  let streamUrl: string | undefined;
  let qualities: Record<string, string> = {};

  if (response.success && response.data) {
    const data = response.data;
    // Check for embed URL
    if (data.embedUrl) {
      streamUrl = data.embedUrl;
    }
    // Check for playlist
    if (data.playlist || data.streamUrl) {
      playlist = data.playlist || data.streamUrl;
    }
    // Check for qualities
    if (data.qualities) {
      qualities = data.qualities;
    }
    // Check for video links (multiple quality options)
    if (data.videoLinks && Array.isArray(data.videoLinks)) {
      for (const link of data.videoLinks) {
        if (link.url && link.quality) {
          qualities[link.quality] = link.url;
        }
      }
    }
  }

  // If no data, check for simple stream URL in response
  if (!playlist && !streamUrl && typeof response === 'string') {
    // Check if response is a direct stream URL
    if (response.includes('.m3u8') || response.includes('.mp4')) {
      streamUrl = response;
    }
  }

  // Check for iframe src in HTML response
  if (!playlist && !streamUrl && response.html) {
    const iframeMatch = response.html.match(/src="([^"]+)"/);
    if (iframeMatch) {
      streamUrl = iframeMatch[1];
    }
  }

  if (!playlist && !streamUrl) {
    throw new NotFoundError('No stream found in vidsrc response');
  }

  ctx.progress(80);

  return {
    embeds: [],
    stream: [
      {
        id: 'vidsrc-primary',
        type: playlist?.includes('.m3u8') ? 'hls' : 'file',
        qualities,
        playlist,
        streamUrl,
        captions: [],
        flags: [],
        headers,
      },
    ],
  };
}

export const vidsrcScraper = makeSourcerer({
  id: 'vidsrc',
  name: 'Vidsrc',
  rank: 320, // Higher priority
  disabled: false,
  flags: [],
  scrapeMovie: comboScraper,
  scrapeShow: comboScraper,
});