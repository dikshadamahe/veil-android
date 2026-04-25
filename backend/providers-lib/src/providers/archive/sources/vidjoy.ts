/* eslint-disable no-console */
import CryptoJS from 'crypto-js';

import { flags } from '@/entrypoint/utils/targets';
import { SourcererEmbed, SourcererOutput, makeSourcerer } from '@/providers/base';
import { MovieScrapeContext } from '@/utils/context';
import { NotFoundError } from '@/utils/errors';

const baseUrl = 'https://vidjoy.pro';
const decryptionKey = '029f3936fb744c4512e66d3a8150c6129472ccdff5b0dd5ec6e512fc06194ef1';

async function comboScraper(ctx: MovieScrapeContext): Promise<SourcererOutput> {
  let apiUrl = `${baseUrl}/embed/api/fastfetch2/${ctx.media.tmdbId}?sr=0`;

  let streamRes = await ctx.proxiedFetcher.full(apiUrl, {
    method: 'GET',
    headers: {
      referer: 'https://vidjoy.pro/',
      origin: 'https://vidjoy.pro',
      'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    },
  });

  if (streamRes.statusCode !== 200) {
    apiUrl = `${baseUrl}/embed/api/fetch2/${ctx.media.tmdbId}?srName=Modread&sr=0`;
    streamRes = await ctx.proxiedFetcher.full(apiUrl, {
      method: 'GET',
      headers: {
        referer: 'https://vidjoy.pro/',
        origin: 'https://vidjoy.pro',
        'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      },
    });
  }

  if (streamRes.statusCode !== 200) {
    throw new NotFoundError('Failed to fetch video source from both endpoints');
  }

  ctx.progress(50);

  const encryptedData = streamRes.body;
  const decrypted = CryptoJS.AES.decrypt(encryptedData, decryptionKey).toString(CryptoJS.enc.Utf8);

  if (!decrypted) {
    throw new NotFoundError('Failed to decrypt video source');
  }

  ctx.progress(70);

  let parsedData;
  try {
    parsedData = JSON.parse(decrypted);
  } catch (error) {
    console.error('JSON parsing error:', error);
    console.error('Decrypted data:', decrypted.substring(0, 200));
    throw new NotFoundError('Failed to parse decrypted video data');
  }

  if (!parsedData.url || !Array.isArray(parsedData.url) || parsedData.url.length === 0) {
    throw new NotFoundError('No video URLs found in response');
  }

  ctx.progress(90);

  const embeds: SourcererEmbed[] = [];

  // Create embeds for each available stream
  parsedData.url.forEach((urlData: any, index: number) => {
    embeds.push({
      embedId: `vidjoy-stream${index + 1}`,
      url: JSON.stringify({
        link: urlData.link,
        type: urlData.type || 'hls',
        lang: urlData.lang || 'English',
        headers: parsedData.headers || {},
      }),
    });
  });

  return {
    embeds,
  };
}

export const vidjoyScraper = makeSourcerer({
  id: 'vidjoy',
  name: 'vidjoy 🔥',
  rank: 185,
  disabled: true,
  flags: [flags.CORS_ALLOWED],
  scrapeMovie: comboScraper,
});
