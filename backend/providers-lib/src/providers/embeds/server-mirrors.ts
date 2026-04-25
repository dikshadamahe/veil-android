import { flags } from '@/entrypoint/utils/targets';
import { makeEmbed } from '@/providers/base';

export const serverMirrorEmbed = makeEmbed({
  id: 'mirror',
  name: 'Mirror',
  rank: 1,
  flags: [flags.CORS_ALLOWED],
  async scrape(ctx) {
    const context = JSON.parse(ctx.url);
    if (context.type === 'hls') {
      return {
        stream: [
          {
            id: 'primary',
            type: 'hls',
            playlist: context.stream,
            headers: context.headers,
            flags: context.flags,
            captions: context.captions,
            skipValidation: context.skipvalid,
          },
        ],
      };
    }
    return {
      stream: [
        {
          id: 'primary',
          type: 'file',
          qualities: context.qualities,
          flags: context.flags,
          captions: context.captions,
          headers: context.headers,
          skipValidation: context.skipvalid,
        },
      ],
    };
  },
});
