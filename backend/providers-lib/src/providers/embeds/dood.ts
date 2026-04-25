/* eslint-disable no-console */
import { customAlphabet } from 'nanoid';

import { flags } from '@/entrypoint/utils/targets';
import { makeEmbed } from '@/providers/base';

const nanoid = customAlphabet('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789', 10);

const PASS_MD5_PATTERNS: RegExp[] = [
  /\$\.get\(['"](\/pass_md5\/[^'"]+)['"]/,
  /\$\.get\(["`](\/pass_md5\/[^"']+)["`]/,
  /\$\.get\s*\(['"](\/pass_md5\/[^'"]+)['"]/,
  /\$\.get\s*\(["`](\/pass_md5\/[^"']+)["`]/,
];

const TOKEN_PATTERNS: RegExp[] = [/token["']?\s*[:=]\s*["']([^"']+)["']/, /makePlay.*?token=([^"&']+)/];

function extractFirst(html: string, patterns: RegExp[]): string | null {
  for (const pat of patterns) {
    const m = pat.exec(html);
    if (m && m[1]) {
      return m[1];
    }
  }
  return null;
}

function resolveAbsoluteUrl(base: string, maybeRelative: string): string {
  try {
    return new URL(maybeRelative, base).toString();
  } catch {
    return maybeRelative;
  }
}

async function extractVideoUrl(ctx: any, streamingLink: string): Promise<string | null> {
  try {
    const headers = {
      'User-Agent':
        'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1',
      Accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Sec-Fetch-Site': 'none',
      'Sec-Fetch-Mode': 'navigate',
      'Accept-Language': 'en-US,en;q=0.9',
      'Sec-Fetch-Dest': 'document',
      Connection: 'keep-alive',
    };

    const response = await ctx.proxiedFetcher.full(streamingLink, {
      headers,
      allowRedirects: true,
    });

    const passMd5Match = extractFirst(response.body, PASS_MD5_PATTERNS);
    if (!passMd5Match) {
      return null;
    }

    const baseUrl = `${response.finalUrl.split('://')[0]}://${response.finalUrl.split('://')[1].split('/')[0]}`;
    const passMd5Url = resolveAbsoluteUrl(baseUrl, passMd5Match);

    const passMd5Response = await ctx.proxiedFetcher(passMd5Url, {
      headers,
      cookies: response.cookies,
    });

    const videoUrl = passMd5Response.trim();

    const tokenMatch = extractFirst(response.body, TOKEN_PATTERNS);
    if (tokenMatch) {
      const randomString = nanoid();
      const expiry = Date.now();
      return `${videoUrl}${randomString}?token=${tokenMatch}&expiry=${expiry}`;
    }

    return videoUrl;
  } catch (e) {
    return null;
  }
}

export const doodScraper = makeEmbed({
  id: 'dood',
  name: 'dood',
  disabled: false,
  rank: 173,
  flags: [flags.CORS_ALLOWED],
  async scrape(ctx) {
    let pageUrl = ctx.url;

    // Replace dood.watch with myvidplay.com to avoid Cloudflare protection
    try {
      const url = new URL(pageUrl);
      if (url.hostname === 'dood.watch') {
        pageUrl = `https://myvidplay.com${url.pathname}${url.search}`;
      }
    } catch {
      // If URL parsing fails, keep original URL
    }

    const redirectReq = await ctx.proxiedFetcher.full(pageUrl);
    pageUrl = redirectReq.finalUrl;

    const videoUrl = await extractVideoUrl(ctx, pageUrl);
    if (!videoUrl) {
      throw new Error('dood: could not extract video URL');
    }

    // Extract thumbnail if available
    const pageResp = await ctx.proxiedFetcher.full(pageUrl, {
      headers: {
        'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        Accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
      },
    });

    const thumbnailMatch = pageResp.body.match(/thumbnails:\s*\{\s*vtt:\s*['"]([^'"]+)['"]/);
    const thumbUrl = thumbnailMatch ? resolveAbsoluteUrl(pageUrl, thumbnailMatch[1]) : null;

    const pageOrigin = new URL(pageUrl).origin;

    return {
      stream: [
        {
          id: 'primary',
          type: 'file',
          flags: [flags.CORS_ALLOWED],
          captions: [],
          qualities: {
            unknown: {
              type: 'mp4',
              url: videoUrl,
            },
          },
          preferredHeaders: {
            Referer: pageOrigin,
          },
          ...(thumbUrl
            ? {
                thumbnailTrack: {
                  type: 'vtt',
                  url: thumbUrl,
                },
              }
            : {}),
        },
      ],
    };
  },
});
