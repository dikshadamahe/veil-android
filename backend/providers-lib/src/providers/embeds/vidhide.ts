import { flags } from '@/entrypoint/utils/targets';
import { makeEmbed } from '@/providers/base';
import type { EmbedScrapeContext } from '@/utils/context';

class Unbaser {
  private ALPHABET: Record<number, string> = {
    62: '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ',
    95: ' !"#$%&\'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~',
  };

  private dictionary: Record<string, number> = {};

  private base: number;

  public unbase!: (value: string) => number;

  constructor(base: number) {
    this.base = base;
    // If base is between 36 and 62, set ALPHABET accordingly
    if (base > 36 && base < 62) {
      this.ALPHABET[base] = this.ALPHABET[base] || this.ALPHABET[62].substring(0, base);
    }
    // If base is between 2 and 36, use parseInt
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
  const juicers = [/}\s*\('(.*)',\s*(\d+|\[\]),\s*(\d+),\s*'(.*)'\.split\('\|'\)/];
  for (const juicer of juicers) {
    const args = juicer.exec(code);
    if (args) {
      try {
        return {
          payload: args[1],
          radix: parseInt(args[2], 10),
          count: parseInt(args[3], 10),
          symtab: args[4].split('|'),
        };
      } catch {
        throw new Error('Corrupted p.a.c.k.e.r. data.');
      }
    }
  }
  throw new Error('Could not make sense of p.a.c.k.e.r data (unexpected code structure)');
}

function unpack(packedCode: string): string {
  const { payload, symtab, radix, count } = _filterargs(packedCode);
  if (count !== symtab.length) throw new Error('Malformed p.a.c.k.e.r. symtab.');
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
  return payload.replace(/\b\w+\b/g, lookup);
}

// Official VidHide domains list
const VIDHIDE_DOMAINS = ['https://vidhidepro.com', 'https://vidhidefast.com', 'https://dinisglows.com'];

function buildOfficialUrl(originalUrl: string, officialDomain: string): string {
  try {
    const u = new URL(originalUrl);
    return `${officialDomain}${u.pathname}${u.search}${u.hash}`;
  } catch {
    return originalUrl;
  }
}

async function fetchWithOfficialDomains(
  ctx: EmbedScrapeContext,
  headers: Record<string, string>,
): Promise<{ html: string; usedUrl: string }> {
  for (const domain of VIDHIDE_DOMAINS) {
    const testUrl = buildOfficialUrl(ctx.url, domain);
    try {
      const html = await ctx.proxiedFetcher<string>(testUrl, { headers });

      if (html && html.includes('eval(function(p,a,c,k,e,d')) {
        return { html, usedUrl: testUrl };
      }
      if (html) {
        return { html, usedUrl: testUrl };
      }
    } catch (err) {
      // Silence errors
    }
  }
  throw new Error('Could not get valid HTML from any official domain');
}

const providers = [
  {
    id: 'vidhide-latino',
    name: 'VidHide (Latino)',
    rank: 13,
  },
  {
    id: 'vidhide-spanish',
    name: 'VidHide (Castellano)',
    rank: 14,
  },
  {
    id: 'vidhide-english',
    name: 'VidHide (English)',
    rank: 15,
  },
];

function extractSubtitles(unpackedScript: string): { file: string; label: string }[] {
  const subtitleRegex = /{file:"([^"]+)",label:"([^"]+)"}/g;
  const results: { file: string; label: string }[] = [];
  const matches = unpackedScript.matchAll(subtitleRegex);
  for (const match of matches) {
    results.push({ file: match[1], label: match[2] });
  }
  return results;
}

function makeVidhideScraper(provider: { id: string; name: string; rank: number }) {
  return makeEmbed({
    id: provider.id,
    name: provider.name,
    rank: provider.rank,
    flags: [flags.IP_LOCKED],
    async scrape(ctx) {
      const headers = {
        Accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
        'Accept-Encoding': '*',
        'Accept-Language': 'en-US,en;q=0.9',
        'User-Agent': 'Mozilla/5.0',
      };

      const { html, usedUrl } = await fetchWithOfficialDomains(ctx, headers);

      const obfuscatedScript = html.match(/<script[^>]*>\s*(eval\(function\(p,a,c,k,e,d.*?\)[\s\S]*?)<\/script>/);
      if (!obfuscatedScript) {
        return { stream: [], embeds: [{ embedId: provider.id, url: ctx.url }] };
      }

      let unpackedScript: string;
      try {
        unpackedScript = unpack(obfuscatedScript[1]);
      } catch (e) {
        return { stream: [], embeds: [{ embedId: provider.id, url: ctx.url }] };
      }

      const m3u8Links = Array.from(unpackedScript.matchAll(/"(http[^"]*?\.m3u8[^"]*?)"/g)).map((m) => m[1]);

      // Only look for links containing master.m3u8
      const masterUrl = m3u8Links.find((url) => url.includes('master.m3u8'));
      if (!masterUrl) {
        return { stream: [], embeds: [{ embedId: provider.id, url: ctx.url }] };
      }
      let videoUrl = masterUrl;

      const subtitles = extractSubtitles(unpackedScript);

      try {
        const m3u8Content = await ctx.proxiedFetcher<string>(videoUrl, {
          headers: { Referer: ctx.url },
        });
        const variants = Array.from(
          m3u8Content.matchAll(/#EXT-X-STREAM-INF:[^\n]+\n(?!iframe)([^\n]*master\.m3u8[^\n]*)/gi),
        );
        if (variants.length > 0) {
          const best = variants[0];
          const base = videoUrl.substring(0, videoUrl.lastIndexOf('/') + 1);
          videoUrl = base + best[1];
        }
        // No else, no index, no fallback
      } catch (e) {
        // Silence variant errors
      }

      const directHeaders = {
        Referer: usedUrl,
        Origin: new URL(usedUrl).origin,
      };

      return {
        stream: [
          {
            id: 'primary',
            type: 'hls',
            playlist: videoUrl,
            headers: directHeaders,
            flags: [flags.IP_LOCKED],
            captions: subtitles.map((s: { file: string; label: string }, idx: number) => {
              const ext = s.file.split('.').pop()?.toLowerCase();
              const type: 'srt' | 'vtt' = ext === 'srt' ? 'srt' : 'vtt';
              return {
                type,
                id: `caption-${idx}`,
                url: s.file,
                hasCorsRestrictions: false,
                language: s.label || 'unknown',
              };
            }),
          },
        ],
      };
    },
  });
}

export const [vidhideLatinoScraper, vidhideSpanishScraper, vidhideEnglishScraper] = providers.map(makeVidhideScraper);

// made by @moonpic
