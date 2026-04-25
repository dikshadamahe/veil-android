import { load } from 'cheerio';
import { unpack } from 'unpacker';

import { makeEmbed } from '@/providers/base';
import { NotFoundError } from '@/utils/errors';

const userAgent =
  'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Mobile Safari/537.36';

export const filemoonScraper = makeEmbed({
  id: 'filemoon',
  name: 'Filemoon',
  rank: 405,
  flags: [],
  async scrape(ctx) {
    const headers = {
      Accept:
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
      Referer: `${new URL(ctx.url).origin}/`,
      'Accept-Language': 'en-GB,en-US;q=0.9,en;q=0.8',
      'sec-ch-ua': '"Not A(Brand";v="8", "Chromium";v="132"',
      'sec-ch-ua-mobile': '?1',
      'sec-ch-ua-platform': '"Android"',
      'Sec-Fetch-Dest': 'iframe',
      'Sec-Fetch-Mode': 'navigate',
      'Sec-Fetch-Site': 'cross-site',
      'Sec-Fetch-User': '?1',
      'Upgrade-Insecure-Requests': '1',
      'User-Agent': userAgent,
    };

    // Fetch initial response
    const response = await ctx.proxiedFetcher<string>(ctx.url, { headers });
    const soup = load(response);

    // Fetch and parse the iframe URL
    const iframe = soup('iframe').first();
    if (!iframe.length) throw new NotFoundError('No iframe found');
    const iframeUrl = iframe.attr('src');
    if (!iframeUrl) throw new NotFoundError('No iframe src found');

    // Get iframe content
    const iframeResponse = await ctx.proxiedFetcher<string>(iframeUrl, { headers });
    const iframeSoup = load(iframeResponse);

    // Find the packed JS code
    const jsCode = iframeSoup('script')
      .filter((_, el) => {
        const text = iframeSoup(el).html() || '';
        return text.includes('eval(function(p,a,c,k,e,d)');
      })
      .first()
      .html();

    if (!jsCode) throw new NotFoundError('No packed JS code found');

    // Unpack the JS code
    const unpacked = unpack(jsCode);
    if (!unpacked) throw new NotFoundError('Failed to unpack JS code');

    // Extract video URL
    const videoMatch = unpacked.match(/file:"([^"]+)"/);
    if (!videoMatch) throw new NotFoundError('No video URL found');
    const videoUrl = videoMatch[1];

    return {
      stream: [
        {
          id: 'primary',
          type: 'hls',
          playlist: videoUrl,
          headers: {
            Referer: `${new URL(ctx.url).origin}/`,
            'User-Agent': userAgent,
          },
          flags: [],
          captions: [],
        },
      ],
    };
  },
});
