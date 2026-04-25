import { load } from 'cheerio';
import { unpack } from 'unpacker';

import { flags } from '@/entrypoint/utils/targets';
import { NotFoundError } from '@/utils/errors';

import { makeEmbed } from '../base';

function extractUrlFromPacked(html: string, patterns: RegExp[]): string {
  const $ = load(html);

  // Find packed script
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

export const supervideoScraper = makeEmbed({
  id: 'supervideo',
  name: 'SuperVideo',
  rank: 130,
  flags: [flags.CORS_ALLOWED],
  scrape: async (ctx) => {
    let url = ctx.url;

    // Normalize URL - replace /e/ and /k/ and /embed- with /
    url = url.replace('/e/', '/').replace('/k/', '/').replace('/embed-', '/');

    const headers = {
      referer: ctx.url,
    };

    let html = await ctx.proxiedFetcher<string>(url, {
      headers,
    });

    // Check if video can only be watched as embed
    if (html.includes('This video can be watched as embed only')) {
      const embedUrl = url.replace(/\/([^/]*)$/, '/e$1');
      html = await ctx.proxiedFetcher<string>(embedUrl, {
        headers: { ...headers, referer: embedUrl },
      });
    }

    // Check for deleted/expired/processing videos
    if (/The file was deleted|The file expired|Video is processing/.test(html)) {
      throw new NotFoundError();
    }

    // Extract m3u8 URL from packed JavaScript
    const m3u8Url = extractUrlFromPacked(html, [/sources:\[{file:"(.*?)"/]);

    return {
      stream: [
        {
          id: 'primary',
          type: 'hls',
          playlist: m3u8Url,
          flags: [flags.CORS_ALLOWED],
          captions: [],
        },
      ],
    };
  },
});
