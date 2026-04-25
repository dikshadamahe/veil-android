import { load } from 'cheerio';
import { unpack } from 'unpacker';

import { flags } from '@/entrypoint/utils/targets';
import { NotFoundError } from '@/utils/errors';

import { makeEmbed } from '../base';

const tracksRegex = /\{file:"([^"]+)",kind:"thumbnails"\}/g;

function extractUrlFromPacked(html: string, patterns: RegExp[]): string {
  const $ = load(html);

  // Find packed script similar to filemoon approach
  const packedScript = $('script')
    .filter((_, el) => {
      const htmlContent = $(el).html();
      return htmlContent != null && htmlContent.includes('eval(function(p,a,c,k,e,d)');
    })
    .first()
    .html();

  if (!packedScript) throw new NotFoundError('Packed script not found');

  try {
    const unpacked = unpack(packedScript);
    for (const pattern of patterns) {
      const match = unpacked.match(pattern);
      if (match?.[1]) {
        return match[1];
      }
    }
  } catch (error) {
    // If unpacking fails, try alternative patterns or fallback
    console.warn('Unpacking failed, trying fallback patterns');
  }

  throw new NotFoundError('Failed to find file URL in packed code');
}

function extractThumbnailTrack(html: string): string | null {
  const $ = load(html);

  // Find packed script
  const packedScript = $('script')
    .filter((_, el) => {
      const htmlContent = $(el).html();
      return htmlContent != null && htmlContent.includes('eval(function(p,a,c,k,e,d)');
    })
    .first()
    .html();

  if (!packedScript) return null;

  try {
    const unpacked = unpack(packedScript);
    const thumbnailMatch = tracksRegex.exec(unpacked);
    return thumbnailMatch?.[1] || null;
  } catch (error) {
    return null;
  }
}

export const droploadScraper = makeEmbed({
  id: 'dropload',
  name: 'Dropload',
  rank: 120,
  flags: [flags.CORS_ALLOWED],
  scrape: async (ctx) => {
    const headers = {
      referer: ctx.url,
    };

    const html = await ctx.proxiedFetcher<string>(ctx.url, {
      headers,
    });

    if (html.includes('File Not Found') || html.includes('Pending in queue')) {
      throw new NotFoundError();
    }

    // Extract playlist URL from packed JavaScript
    const playlistUrl = extractUrlFromPacked(html, [/sources:\[{file:"(.*?)"/]);

    const mainPageUrl = new URL(ctx.url);

    // Extract thumbnail track if available
    const thumbnailTrack = extractThumbnailTrack(html);

    return {
      stream: [
        {
          id: 'primary',
          type: 'hls',
          playlist: playlistUrl,
          flags: [flags.CORS_ALLOWED],
          captions: [],
          ...(thumbnailTrack && {
            thumbnailTrack: {
              type: 'vtt',
              url: mainPageUrl.origin + thumbnailTrack,
            },
          }),
        },
      ],
    };
  },
});
