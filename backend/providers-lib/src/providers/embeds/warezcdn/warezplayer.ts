import { makeEmbed } from '@/providers/base';

export const warezPlayerScraper = makeEmbed({
  id: 'warezplayer',
  name: 'warezPLAYER',
  disabled: true,
  rank: 85,
  flags: [],
  async scrape(ctx) {
    // ex url: https://basseqwevewcewcewecwcw.xyz/video/0e4a2c65bdaddd66a53422d93daebe68
    const playerPageUrl = new URL(ctx.url);

    const hash = playerPageUrl.pathname.split('/')[2];
    const playerApiRes = await ctx.proxiedFetcher('/player/index.php', {
      baseUrl: playerPageUrl.origin,
      query: {
        data: hash,
        do: 'getVideo',
      },
      method: 'POST',
      body: new URLSearchParams({
        hash,
      }),
      headers: {
        'X-Requested-With': 'XMLHttpRequest',
      },
    });
    const sources = JSON.parse(playerApiRes); // json isn't parsed by fetcher due to content-type being text/html.
    if (!sources.videoSource) throw new Error('Playlist not found');

    return {
      stream: [
        {
          id: 'primary',
          type: 'hls',
          flags: [],
          captions: [],
          playlist: sources.videoSource,
          headers: {
            // without this it returns "security error"
            Accept: '*/*',
          },
        },
      ],
    };
  },
});
