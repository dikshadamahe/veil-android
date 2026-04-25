import { flags } from '@/entrypoint/utils/targets';
import { makeEmbed } from '@/providers/base';
import { NotFoundError } from '@/utils/errors';

const userAgent =
  'Mozilla/5.0 (Linux; Android 11; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

function cleanSymbols(s: string): string {
  let result = s;
  for (const p of ['@$', '^^', '~@', '%?', '*~', '!!', '#&']) {
    result = result.replaceAll(p, '_');
  }
  return result;
}

function cleanUnderscores(s: string): string {
  return s.replace(/_/g, '');
}

function shiftBack(s: string, n: number): string {
  return Array.from(s)
    .map((c) => String.fromCharCode(c.charCodeAt(0) - n))
    .join('');
}

function rot13(str: string): string {
  return str.replace(/[a-zA-Z]/g, (c) => {
    const base = c <= 'Z' ? 65 : 97;
    return String.fromCharCode(((c.charCodeAt(0) - base + 13) % 26) + base);
  });
}

export const voeScraper = makeEmbed({
  id: 'voe',
  name: 'Voe',
  rank: 180,
  flags: [flags.IP_LOCKED],
  async scrape(ctx) {
    const url = ctx.url;
    const defaultDomain = (() => {
      try {
        const u = new URL(url);
        return `${u.protocol}//${u.host}/`;
      } catch {
        return undefined;
      }
    })();

    const headers: Record<string, string> = {
      'User-Agent': userAgent,
    };
    if (defaultDomain) {
      headers.Referer = defaultDomain;
    }

    let html = await ctx.proxiedFetcher<string>(url, { headers });

    // Handle redirect page
    if (html.includes('Redirecting...')) {
      const match = html.match(/href\s*=\s*'(.*?)';/);
      if (!match) throw new NotFoundError('Redirect target not found');
      const redirectUrl = match[1];
      html = await ctx.proxiedFetcher<string>(redirectUrl, { headers });
    }

    const jsonScriptMatch = html.match(/<script[^>]+type=["']application\/json["'][^>]*>([\s\S]*?)<\/script>/i);
    if (!jsonScriptMatch) throw new NotFoundError('Obfuscated script not found');

    const obfuscatedScript = jsonScriptMatch[1];
    const encodedMatch = obfuscatedScript.match(/\["(.*?)"\]/);
    if (!encodedMatch) throw new NotFoundError('Encoded data not found');

    const encodedData = encodedMatch[1];

    // Decoding steps
    let decoded = rot13(encodedData);
    decoded = cleanSymbols(decoded);
    decoded = cleanUnderscores(decoded);
    decoded = Buffer.from(decoded, 'base64').toString('utf-8');
    decoded = shiftBack(decoded, 3);
    decoded = decoded.split('').reverse().join('');
    decoded = Buffer.from(decoded, 'base64').toString('utf-8');

    const json = JSON.parse(decoded);
    const videoUrl = json?.source;
    if (!videoUrl) throw new NotFoundError('No video URL found');

    return {
      stream: [
        {
          id: 'primary',
          type: 'hls',
          playlist: videoUrl,
          flags: [flags.IP_LOCKED],
          captions: [],
          headers: {
            Referer: defaultDomain || url,
            Origin: defaultDomain?.replace(/\/$/, '') || new URL(url).origin,
            'User-Agent': userAgent,
          },
        },
      ],
    };
  },
});
