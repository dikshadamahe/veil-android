import { flags } from '@/entrypoint/utils/targets';
import { makeEmbed } from '@/providers/base';

// Thanks to Paradox_77 for helping with the decryption
function hexToChar(hex: string): string {
  return String.fromCharCode(parseInt(hex, 16));
}

function decrypt(data: string, key: string): string {
  const formatedData = data.match(/../g)?.map(hexToChar).join('') || '';
  return formatedData
    .split('')
    .map((char, i) => String.fromCharCode(char.charCodeAt(0) ^ key.charCodeAt(i % key.length)))
    .join('');
}

export const turbovidScraper = makeEmbed({
  id: 'turbovid',
  name: 'Turbovid',
  rank: 122,
  flags: [flags.CORS_ALLOWED],
  async scrape(ctx) {
    const baseUrl = new URL(ctx.url).origin;
    const embedPage = await ctx.proxiedFetcher(ctx.url);

    ctx.progress(30);

    // the whitespace is for future-proofing the regex a bit
    const apkey = embedPage.match(/const\s+apkey\s*=\s*"(.*?)";/)?.[1];
    const xxid = embedPage.match(/const\s+xxid\s*=\s*"(.*?)";/)?.[1];

    if (!apkey || !xxid) throw new Error('Failed to get required values');

    // json isn't parsed by proxiedFetcher due to content-type being text/html
    const encodedJuiceKey = JSON.parse(
      await ctx.proxiedFetcher('/api/cucked/juice_key', {
        baseUrl,
        headers: {
          referer: ctx.url,
          'User-Agent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36',
          Accept: '*/*',
          'Accept-Language': 'en-US,en;q=0.9',
          Connection: 'keep-alive',
          'Content-Type': 'application/json',
          'X-Turbo': 'TurboVidClient',
          'Sec-Fetch-Dest': 'empty',
          'Sec-Fetch-Mode': 'cors',
          'Sec-Fetch-Site': 'same-origin',
        },
      }),
    ).juice;

    if (!encodedJuiceKey) throw new Error('Failed to fetch the key');

    const juiceKey = atob(encodedJuiceKey);

    ctx.progress(60);

    const data = JSON.parse(
      await ctx.proxiedFetcher('/api/cucked/the_juice_v2/', {
        baseUrl,
        query: {
          [apkey]: xxid,
        },
        headers: {
          'User-Agent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36',
          Accept: '*/*',
          'Accept-Language': 'en-US,en;q=0.9',
          Connection: 'keep-alive',
          'Content-Type': 'application/json',
          'X-Turbo': 'TurboVidClient',
          'Sec-Fetch-Dest': 'empty',
          'Sec-Fetch-Mode': 'cors',
          'Sec-Fetch-Site': 'same-origin',
          referer: ctx.url,
        },
      }),
    ).data;

    if (!data) throw new Error('Failed to fetch required data');

    ctx.progress(90);

    const playlist = decrypt(data, juiceKey);

    const streamHeaders = {
      referer: `${baseUrl}/`,
      origin: baseUrl,
    };

    return {
      stream: [
        {
          type: 'hls',
          id: 'primary',
          playlist,
          preferredHeaders: streamHeaders,
          flags: [flags.CORS_ALLOWED],
          captions: [],
        },
      ],
    };
  },
});
