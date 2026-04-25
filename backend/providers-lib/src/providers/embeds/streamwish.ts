/* eslint-disable no-console */

// --------
// READ
// There will be an ssl certificate error, you must use Node.js fetcher or browser fetcher.
// $ NODE_TLS_REJECT_UNAUTHORIZED=0 npm run cli -- --fetcher node-fetch --source-id streamwish-japanese --url "https://streamwish.to/e/abcdefc123"
// --------

import { flags } from '@/entrypoint/utils/targets';
import { makeEmbed } from '@/providers/base';
import { createM3U8ProxyUrl } from '@/utils/proxy';

class Unbaser {
  private ALPHABET: Record<number, string> = {
    62: '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ',
    95: "' !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~'",
  };

  private dictionary: Record<string, number> = {};

  private base: number;

  public unbase: (value: string) => number;

  constructor(base: number) {
    this.base = base;

    if (base > 36 && base < 62) {
      this.ALPHABET[base] = this.ALPHABET[base] || this.ALPHABET[62].substring(0, base);
    }

    if (base >= 2 && base <= 36) {
      this.unbase = (value: string) => parseInt(value, base);
    } else {
      try {
        [...this.ALPHABET[base]].forEach((cipher, index) => {
          this.dictionary[cipher] = index;
        });
      } catch {
        throw new Error('Unsupported base encoding.');
      }

      this.unbase = this._dictunbaser.bind(this);
    }
  }

  private _dictunbaser(value: string): number {
    let ret = 0;
    [...value].reverse().forEach((cipher, index) => {
      ret += this.base ** index * this.dictionary[cipher];
    });
    return ret;
  }
}

function _filterargs(code: string) {
  const juicers = [
    /}\('(.*)', *(\d+|\[\]), *(\d+), *'(.*)'\.split\('\|'\), *(\d+), *(.*)\)\)/,
    /}\('(.*)', *(\d+|\[\]), *(\d+), *'(.*)'\.split\('\|'\)/,
  ];

  for (const juicer of juicers) {
    const args = juicer.exec(code);
    if (args) {
      try {
        return {
          payload: args[1],
          symtab: args[4].split('|'),
          radix: parseInt(args[2], 10),
          count: parseInt(args[3], 10),
        };
      } catch {
        throw new Error('Corrupted p.a.c.k.e.r. data.');
      }
    }
  }

  throw new Error('Could not make sense of p.a.c.k.e.r data (unexpected code structure)');
}

function _replacestrings(str: string): string {
  return str;
}

function unpack(packedCode: string): string {
  const { payload, symtab, radix, count } = _filterargs(packedCode);

  if (count !== symtab.length) {
    throw new Error('Malformed p.a.c.k.e.r. symtab.');
  }

  let unbase: Unbaser;
  try {
    unbase = new Unbaser(radix);
  } catch {
    throw new Error('Unknown p.a.c.k.e.r. encoding.');
  }

  const lookup = (match: string): string => {
    const word = match;
    const word2 = radix === 1 ? symtab[parseInt(word, 10)] : symtab[unbase.unbase(word)];
    return word2 || word;
  };

  const replaced = payload.replace(/\b\w+\b/g, lookup);
  return _replacestrings(replaced);
}

const providers = [
  {
    id: 'streamwish-japanese',
    name: 'StreamWish (Japanese Sub Español)',
    rank: 171,
  },
  {
    id: 'streamwish-latino',
    name: 'streamwish (latino)',
    rank: 170,
  },
  {
    id: 'streamwish-spanish',
    name: 'streamwish (castellano)',
    rank: 169,
  },
  {
    id: 'streamwish-english',
    name: 'streamwish (english)',
    rank: 168,
  },
];

function embed(provider: { id: string; name: string; rank: number; disabled?: boolean }) {
  return makeEmbed({
    id: provider.id,
    name: provider.name,
    rank: provider.rank,
    flags: [flags.CORS_ALLOWED],
    disabled: provider.disabled,
    async scrape(ctx) {
      const headers = {
        Accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
        'Accept-Encoding': '*',
        'Accept-Language': 'en-US,en;q=0.9',
        'User-Agent':
          'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
      };

      const domains = [
        'hgplaycdn.com',
        'habetar.com',
        'yuguaab.com',
        'guxhag.com',
        'auvexiug.com',
        'xenolyzb.com',
        'tryzendm.com',
      ];
      ctx.url = `https://${domains[Math.floor(Math.random() * domains.length)]}${ctx.url.replace('https://streamwish.to', '')}`;

      let html: string;
      try {
        html = await ctx.proxiedFetcher<string>(ctx.url, { headers });
      } catch (error) {
        console.error(`Error:`, {
          message: error instanceof Error ? error.message : 'Unknown error',
          cause: (error as any).cause || undefined,
          url: ctx.url,
        });
        throw error;
      }
      const obfuscatedScript = html.match(/<script[^>]*>\s*(eval\(function\(p,a,c,k,e,d.*?\)[\s\S]*?)<\/script>/);

      if (!obfuscatedScript) {
        return { stream: [], embeds: [{ embedId: provider.id, url: ctx.url }] };
      }

      let unpackedScript: string;
      try {
        unpackedScript = unpack(obfuscatedScript[1]);
      } catch {
        return { stream: [], embeds: [{ embedId: provider.id, url: ctx.url }] };
      }

      const hls2Match = unpackedScript.match(/"hls2"\s*:\s*"([^"]+)"/);
      if (!hls2Match) {
        return { stream: [], embeds: [{ embedId: provider.id, url: ctx.url }] };
      }

      let videoUrl = hls2Match[1];

      if (!/^https?:\/\//.test(videoUrl)) {
        videoUrl = `https://swiftplayers.com/${videoUrl.replace(/^\/+/, '')}`;
      }

      const videoHeaders = {
        Referer: ctx.url,
        Origin: ctx.url,
      };

      return {
        stream: [
          {
            id: 'primary',
            type: 'hls',
            playlist: createM3U8ProxyUrl(videoUrl, ctx.features, videoHeaders),
            headers: videoHeaders,
            flags: [flags.CORS_ALLOWED],
            captions: [],
          },
        ],
        embeds: [],
      };
    },
  });
}

export const [streamwishLatinoScraper, streamwishSpanishScraper, streamwishEnglishScraper, streamwishJapaneseScraper] =
  providers.map(embed);

// made by @moonpic
