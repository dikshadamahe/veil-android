import CryptoJS from 'crypto-js';

import { flags } from '@/entrypoint/utils/targets';
import { SourcererOutput, makeSourcerer } from '@/providers/base';
import { MovieScrapeContext, ShowScrapeContext } from '@/utils/context';
import { NotFoundError } from '@/utils/errors';

const headers = {
  Origin: 'https://vidrock.net',
  Referer: 'https://vidrock.net/',
};

const passphrase = 'x7k9mPqT2rWvY8zA5bC3nF6hJ2lK4mN9';
const key = CryptoJS.enc.Utf8.parse(passphrase);
const iv = CryptoJS.enc.Utf8.parse(passphrase.substring(0, 16));

const baseUrl = 'https://vidrock.net/api';
const userAgent =
  'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Mobile Safari/537.36';

async function comboScraper(ctx: ShowScrapeContext | MovieScrapeContext): Promise<SourcererOutput> {
  const itemType = ctx.media.type;
  let itemId: string;

  if (itemType === 'movie') {
    itemId = ctx.media.tmdbId;
  } else {
    itemId = `${ctx.media.tmdbId}_${ctx.media.season.number}_${ctx.media.episode.number}`;
  }

  const encrypted = CryptoJS.AES.encrypt(itemId, key, {
    iv,
    mode: CryptoJS.mode.CBC,
    padding: CryptoJS.pad.Pkcs7,
  });

  let encryptedBase64 = encrypted.ciphertext.toString(CryptoJS.enc.Base64);

  encryptedBase64 = encryptedBase64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

  const encoded = encodeURIComponent(encryptedBase64);

  const url = `${baseUrl}/${itemType}/${encoded}`;

  const res = await ctx.proxiedFetcher<any>(url, {
    headers: {
      ...headers,
      'User-Agent': userAgent,
    },
  });

  let parsedRes = res;

  if (typeof res === 'string') {
    try {
      parsedRes = JSON.parse(res);
    } catch (e) {
      throw new NotFoundError('No sources found from Vidrock API: Invalid JSON response');
    }
  }

  if (!parsedRes || typeof parsedRes !== 'object' || Array.isArray(parsedRes)) {
    throw new NotFoundError('No sources found from Vidrock API: Invalid response');
  }

  const embeds = [];

  const createMirrorEmbed = (serverName: string, serverData: any) => {
    if (!serverData?.url) return null;
    if (serverName.includes('Astra') || serverData.url.includes('.workers.dev')) return null;

    const context = {
      type: 'hls',
      stream: serverData.url,
      headers,
      flags: [flags.CORS_ALLOWED],
      captions: [],
    };

    return {
      embedId: 'mirror',
      url: JSON.stringify(context),
    };
  };

  for (const sourceKey of Object.keys(parsedRes)) {
    const sourceData = parsedRes[sourceKey];
    if (sourceData?.url && sourceData.url !== null) {
      // Handle Atlas server which returns a playlist URL
      if (sourceKey === 'Atlas' || sourceData.url.includes('cdn.vidrock.store/playlist/')) {
        try {
          const playlistRes = await ctx.proxiedFetcher<any>(sourceData.url, {
            headers: {
              ...headers,
              'User-Agent': userAgent,
            },
          });

          let playlistData = playlistRes;
          if (typeof playlistRes === 'string') {
            try {
              playlistData = JSON.parse(playlistRes);
            } catch (e) {
              continue;
            }
          }

          if (Array.isArray(playlistData) && playlistData.length > 0) {
            // Build qualities object from playlist
            const qualities: Record<string, { type: 'mp4'; url: string }> = {};

            for (const stream of playlistData) {
              if (stream?.url && stream?.resolution) {
                const resolution = stream.resolution.toString();
                qualities[resolution] = {
                  type: 'mp4',
                  url: stream.url,
                };
              }
            }

            if (Object.keys(qualities).length > 0) {
              const context = {
                type: 'file',
                qualities,
                headers,
                flags: [flags.CORS_ALLOWED],
                captions: [],
              };

              embeds.push({
                embedId: 'mirror',
                url: JSON.stringify(context),
              });
            }
          }
        } catch (e) {
          // If playlist fetch fails, skip this source
          continue;
        }
      } else {
        const embed = createMirrorEmbed(sourceKey, sourceData);
        if (embed) embeds.push(embed);
      }
    }
  }

  if (embeds.length === 0) {
    throw new NotFoundError('No valid sources found from Vidrock API');
  }

  return {
    embeds,
  };
}

export const vidrockScraper = makeSourcerer({
  id: 'vidrock',
  name: 'Granite',
  rank: 170,
  disabled: false,
  flags: [],
  scrapeMovie: comboScraper,
  scrapeShow: comboScraper,
});
