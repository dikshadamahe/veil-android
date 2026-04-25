import { flags } from '@/entrypoint/utils/targets';
import { makeEmbed } from '@/providers/base';
import { NotFoundError } from '@/utils/errors';

import { fileMoonScraper } from './index';

export const fileMoonMp4Scraper = makeEmbed({
  id: 'filemoon-mp4',
  name: 'Filemoon MP4',
  rank: 406,
  flags: [flags.IP_LOCKED],
  async scrape(ctx) {
    const result = await fileMoonScraper.scrape(ctx);
    if (!result.stream || result.stream.length === 0) throw new NotFoundError('Failed to find result');
    if (result.stream[0].type !== 'hls') throw new NotFoundError('Failed to find hls stream');

    const mp4Url = result.stream[0].playlist.replace(/\/hls2\//, '/download/').replace(/\.m3u8.*/, '.mp4');

    return {
      stream: [
        {
          id: 'primary',
          type: 'file',
          qualities: {
            unknown: {
              type: 'mp4',
              url: mp4Url,
            },
          },
          flags: [flags.IP_LOCKED],
          captions: result.stream[0].captions,
        },
      ],
    };
  },
});
