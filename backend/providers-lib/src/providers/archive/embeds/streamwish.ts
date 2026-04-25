import * as unpacker from 'unpacker';

import { flags } from '@/entrypoint/utils/targets';
import { makeEmbed } from '@/providers/base';

const packedRegex = /(eval\(function\(p,a,c,k,e,d\).*\)\)\))/;
const linkRegex = /file:"(https:\/\/[^"]+)"/;

export const streamwishScraper = makeEmbed({
  id: 'streamwish',
  name: 'Streamwish',
  rank: 216,
  flags: [flags.CORS_ALLOWED],
  async scrape(ctx) {
    const streamRes = await ctx.proxiedFetcher<string>(ctx.url);
    const packed = streamRes.match(packedRegex);

    if (!packed) throw new Error('Packed not found');

    const unpacked = unpacker.unpack(packed[1]);
    const link = unpacked.match(linkRegex);

    if (!link) throw new Error('Stream not found');
    return {
      stream: [
        {
          type: 'hls',
          id: 'primary',
          playlist: link[1],
          flags: [flags.CORS_ALLOWED],
          captions: [],
        },
      ],
    };
  },
});
