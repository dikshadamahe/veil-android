import { load } from 'cheerio';
import { unpack } from 'unpacker';

import { makeEmbed } from '@/providers/base';
import { NotFoundError } from '@/utils/errors';

export const filelionsScraper = makeEmbed({
  id: 'filelions',
  name: 'Filelions',
  rank: 115,
  flags: [],
  async scrape(ctx) {
    const html = await ctx.proxiedFetcher<string>(ctx.url, {
      headers: {
        Referer: 'https://primesrc.me/',
      },
    });

    const $ = load(html);
    const packedScript = $('script')
      .filter((_, el) => {
        const htmlContent = $(el).html();
        return htmlContent != null && htmlContent.includes('eval(function(p,a,c,k,e,d)');
      })
      .first()
      .html();
    if (!packedScript) throw new NotFoundError('Packed script not found');

    const evalMatch = packedScript.match(/eval\((.*)\)/);
    if (!evalMatch) throw new NotFoundError('Eval code not found');

    const unpacked = unpack(evalMatch[1]);

    const linksMatch = unpacked.match(/var links=(\{.*?\})/);
    if (!linksMatch) throw new NotFoundError('Links object not found');

    const links = JSON.parse(linksMatch[1]);
    Object.keys(links).forEach((key) => {
      if (links[key].startsWith('/stream/')) {
        links[key] = `https://dinisglows.com${links[key]}`;
      }
    });

    const streamUrl = links.hls4 || Object.values(links)[0];
    if (!streamUrl) throw new NotFoundError('No stream URL found');

    return {
      stream: [
        {
          id: 'primary',
          type: 'hls',
          playlist: streamUrl,
          headers: {
            Referer: 'https://primesrc.me/',
          },
          flags: [],
          captions: [],
        },
      ],
    };
  },
});
