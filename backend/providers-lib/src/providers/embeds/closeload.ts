import { load } from 'cheerio';
import { unpack } from 'unpacker';

import { flags } from '@/entrypoint/utils/targets';
import { NotFoundError } from '@/utils/errors';

import { makeEmbed } from '../base';
import { Caption, getCaptionTypeFromUrl, labelToLanguageCode } from '../captions';

// Custom base64 decoder for problematic strings
function customAtob(input: string): string {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
  const str = input.replace(/=+$/, '');
  let output = '';
  if (str.length % 4 === 1) {
    throw new Error('The string to be decoded is not correctly encoded.');
  }
  for (let bc = 0, bs = 0, i = 0; i < str.length; i++) {
    const buffer = str.charAt(i);
    const charIndex = chars.indexOf(buffer);
    if (charIndex === -1) continue;
    bs = bc % 4 ? bs * 64 + charIndex : charIndex;
    if (bc++ % 4) {
      output += String.fromCharCode(255 & (bs >> ((-2 * bc) & 6)));
    }
  }
  return output;
}

// Implement the closeload decoding function
function decodeCloseload(valueParts: string[]): string {
  const value = valueParts.join('');
  let result = value;

  // Step 1: base64 decode
  result = atob(result);

  // Step 2: ROT13-like transformation
  result = result.replace(/[a-zA-Z]/g, function rot13Transform(c) {
    const charCode = c.charCodeAt(0);
    const newCharCode = charCode + 13;
    const maxCode = c <= 'Z' ? 90 : 122;
    return String.fromCharCode(newCharCode <= maxCode ? newCharCode : newCharCode - 26);
  });

  // Step 3: reverse the string
  result = result.split('').reverse().join('');

  // Step 4: custom unmixing
  let unmix = '';
  for (let i = 0; i < result.length; i++) {
    let charCode = result.charCodeAt(i);
    charCode = (charCode - (399756995 % (i + 5)) + 256) % 256;
    unmix += String.fromCharCode(charCode);
  }

  return unmix;
}

const referer = 'https://ridomovies.tv/';

export const closeLoadScraper = makeEmbed({
  id: 'closeload',
  name: 'CloseLoad',
  rank: 106,
  flags: [flags.IP_LOCKED],
  disabled: true,
  async scrape(ctx) {
    const baseUrl = new URL(ctx.url).origin;

    const iframeRes = await ctx.proxiedFetcher<string>(ctx.url, {
      headers: { referer },
    });
    const iframeRes$ = load(iframeRes);
    const captions: Caption[] = iframeRes$('track')
      .map((_, el) => {
        const track = iframeRes$(el);
        const url = `${baseUrl}${track.attr('src')}`;
        const label = track.attr('label') ?? '';
        const language = labelToLanguageCode(label);
        const captionType = getCaptionTypeFromUrl(url);

        if (!language || !captionType) return null;
        return {
          id: url,
          language,
          hasCorsRestrictions: true,
          type: captionType,
          url,
        };
      })
      .get()
      .filter((x) => x !== null);

    const evalCode = iframeRes$('script')
      .filter((_, el) => {
        const script = iframeRes$(el);
        return (script.attr('type') === 'text/javascript' && script.html()?.includes('p,a,c,k,e,d')) ?? false;
      })
      .html();
    if (!evalCode) throw new Error("Couldn't find eval code");

    const decoded = unpack(evalCode);

    let base64EncodedUrl: string | undefined;

    // Look for the dc_* function call pattern (function names are dynamic)
    const functionCallMatch = decoded.match(/dc_\w+\(\[([^\]]+)\]\)/);
    if (functionCallMatch) {
      // Extract the array of strings passed to the function
      const arrayContent = functionCallMatch[1];

      // Parse the array of strings
      const stringMatches = arrayContent.match(/"([^"]+)"/g);
      if (stringMatches) {
        // Extract the strings from the array
        const valueParts = stringMatches.map((s) => s.slice(1, -1));

        // Use the closeload decoding function
        try {
          const decodedUrl = decodeCloseload(valueParts);

          // Check if the decoded result looks like a URL
          if (decodedUrl.startsWith('http://') || decodedUrl.startsWith('https://')) {
            base64EncodedUrl = decodedUrl; // This will be the final URL, not base64
          }
        } catch (error) {
          // Continue to fallback patterns if decoding fails
        }
      }
    }

    // Fallback to original patterns if function call not found
    if (!base64EncodedUrl) {
      const patterns = [/var\s+(\w+)\s*=\s*"([^"]+)";/g, /(\w+)\s*=\s*"([^"]+)"/g, /"([A-Za-z0-9+/=]+)"/g];

      for (const pattern of patterns) {
        const match = pattern.exec(decoded);
        if (match) {
          const potentialUrl = match[2] || match[1];
          // Check if it looks like base64
          if (/^[A-Za-z0-9+/]*={0,2}$/.test(potentialUrl) && potentialUrl.length > 10) {
            base64EncodedUrl = potentialUrl;
            break;
          }
        }
      }
    }
    if (!base64EncodedUrl) throw new NotFoundError('Unable to find source url');

    // If base64EncodedUrl is already a URL (from closeload decoding), use it directly
    let url: string;
    if (base64EncodedUrl.startsWith('http://') || base64EncodedUrl.startsWith('https://')) {
      url = base64EncodedUrl;
    } else {
      // Fallback to original base64 decoding logic
      // Validate base64 string before decoding
      const isValidBase64 = /^[A-Za-z0-9+/]*={0,2}$/.test(base64EncodedUrl);
      if (!isValidBase64) {
        throw new NotFoundError('Invalid base64 encoding found in source url');
      }

      let decodedString: string;
      try {
        decodedString = atob(base64EncodedUrl);
      } catch (error) {
        // Try custom decoder as fallback
        try {
          decodedString = customAtob(base64EncodedUrl);
        } catch (customError) {
          throw new NotFoundError(`Failed to decode base64 source url: ${base64EncodedUrl.substring(0, 50)}...`);
        }
      }

      // Try to find a URL in the decoded string
      const urlMatch = decodedString.match(/(https?:\/\/[^\s"']+)/);
      if (urlMatch) {
        url = urlMatch[1];
      } else if (decodedString.startsWith('http://') || decodedString.startsWith('https://')) {
        url = decodedString;
      } else {
        throw new NotFoundError(`Decoded string is not a valid URL: ${decodedString.substring(0, 100)}...`);
      }
    }
    return {
      stream: [
        {
          id: 'primary',
          type: 'hls',
          playlist: url,
          captions,
          flags: [flags.IP_LOCKED],
          headers: {
            Referer: 'https://closeload.top/',
            Origin: 'https://closeload.top',
          },
        },
      ],
    };
  },
});
