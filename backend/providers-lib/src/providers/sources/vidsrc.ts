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

  // vsembed returns HTML, not JSON - fetch directly without using proxiedFetcher for HTML parsing
  const fetchResult = await ctx.fetcher(embedUrl, {
    method: 'GET',
    headers,
  });

  ctx.progress(60);

  if (!fetchResult) {
    throw new NotFoundError('No response from vidsrc');
  }

  let playlist: string | undefined;
  let streamUrl: string | undefined;
  let qualities: Record<string, string> = {};

  // Handle string response (HTML)
  if (typeof fetchResult === 'string') {
    const html = fetchResult;

    // Check for embed URL in data-config attribute
    const configMatch = html.match(/data-config=["']([^"']+)["']/);
    if (configMatch) {
      try {
        const configUrl = decodeURIComponent(configMatch[1]);
        // Try to extract stream URL from config
        if (configUrl.includes('.m3u8') || configUrl.includes('.mp4')) {
          streamUrl = configUrl;
        } else {
          // Try fetching the config URL as JSON
          const configResponse = await ctx.fetcher(configUrl, { headers });
          if (configResponse && typeof configResponse === 'object') {
            const config = configResponse as any;
            if (config.file) {
              streamUrl = config.file;
            }
            if (config.playlist) {
              playlist = config.playlist;
            }
          }
        }
      } catch (_) {
        // Ignore config parsing errors
      }
    }

    // Check for iframe with stream URL
    if (!streamUrl && !playlist) {
      const iframeMatch = html.match(/<iframe[^>]+src=["']([^"']+)["']/i);
      if (iframeMatch) {
        streamUrl = iframeMatch[1];
      }
    }

    // Check for video file URLs directly in HTML
    if (!streamUrl && !playlist) {
      const videoMatch = html.match(/file:\s*["']([^"']+\.(m3u8|mp4)[^"']*)["']/i);
      if (videoMatch) {
        streamUrl = videoMatch[1];
      }
    }
  }

  // Handle JSON response (if vsembed returns JSON in some cases)
  if (!playlist && !streamUrl && typeof fetchResult === 'object') {
    const data = fetchResult as any;
    if (data.embedUrl) {
      streamUrl = data.embedUrl;
    }
    if (data.playlist || data.streamUrl) {
      playlist = data.playlist || data.streamUrl;
    }
    if (data.qualities) {
      qualities = data.qualities;
    }
    if (data.videoLinks && Array.isArray(data.videoLinks)) {
      for (const link of data.videoLinks) {
        if (link.url && link.quality) {
          qualities[link.quality] = link.url;
        }
      }
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