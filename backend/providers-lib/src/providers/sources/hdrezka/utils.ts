import { getCaptionTypeFromUrl, labelToLanguageCode } from '@/providers/captions';
import { FileBasedStream } from '@/providers/streams';
import { NotFoundError } from '@/utils/errors';
import { getValidQualityFromString } from '@/utils/quality';

function generateRandomFavs(): string {
  const randomHex = () => Math.floor(Math.random() * 16).toString(16);
  const generateSegment = (length: number) => Array.from({ length }, randomHex).join('');

  return `${generateSegment(8)}-${generateSegment(4)}-${generateSegment(4)}-${generateSegment(4)}-${generateSegment(
    12,
  )}`;
}

function parseSubtitleLinks(inputString?: string | boolean): FileBasedStream['captions'] {
  if (!inputString || typeof inputString === 'boolean') return [];
  const linksArray = inputString.split(',');
  const captions: FileBasedStream['captions'] = [];

  linksArray.forEach((link) => {
    const match = link.match(/\[([^\]]+)\](https?:\/\/\S+?)(?=,\[|$)/);

    if (match) {
      const type = getCaptionTypeFromUrl(match[2]);
      const language = labelToLanguageCode(match[1]);
      if (!type || !language) return;

      captions.push({
        id: match[2],
        language,
        hasCorsRestrictions: false,
        type,
        url: match[2],
      });
    }
  });

  return captions;
}

// function getData(x: string): Record<string, string> {
//   const v: Record<string, string> = {
//     file3_separator: '//_//',
//     bk0: '$$#!!@#!@##',
//     bk1: '^^^!@##!!##',
//     bk2: '####^!!##!@@',
//     bk3: '@@@@@!##!^^^',
//     bk4: '$$!!@$$@^!@#$$@',
//   };
//   let a = x.substr(2);
//   for (let i = 4; i >= 0; i--) {
//     const key = `bk${i}`;
//     if (v[key]) {
//       a = a.replace(
//         v.file3_separator +
//           Buffer.from(
//             encodeURIComponent(v[key]).replace(/%([0-9A-F]{2})/g, (_, p1) => String.fromCharCode(parseInt(p1, 16))),
//           ).toString('base64'),
//         '',
//       );
//     }
//   }
//   try {
//     a = decodeURIComponent(
//       Buffer.from(a, 'base64')
//         .toString()
//         .split('')
//         .map((c) => `%${`00${c.charCodeAt(0).toString(16)}`.slice(-2)}`)
//         .join(''),
//     );
//   } catch (e) {
//     a = '';
//   }
//   return a.split(',').reduce(
//     (m, ele) => {
//       const [key, value] = ele.split(']');
//       m[key.replace('[', '')] = value;
//       return m;
//     },
//     {} as Record<string, string>,
//   );
// }

function parseVideoLinks(inputString?: string): FileBasedStream['qualities'] {
  if (!inputString) throw new NotFoundError('No video links found');

  try {
    const qualityMap: Record<string, { type: 'mp4'; url: string }> = {};
    const links = inputString.split(',');

    links.forEach((link) => {
      const match = link.match(/\[([^\]]+)\](https?:\/\/[^\s,]+)/);
      if (match) {
        // eslint-disable-next-line @typescript-eslint/no-unused-vars
        const [_, quality, url] = match;
        // Skip premium qualities that are null
        if (url === 'null') return;

        // Normalize quality (remove HTML tags and convert to lowercase)
        const normalizedQuality = quality
          .replace(/<[^>]+>/g, '') // Remove HTML tags
          .toLowerCase()
          .replace('p', '')
          .trim();

        qualityMap[normalizedQuality] = {
          type: 'mp4',
          url: url.trim(),
        };
      }
    });

    // Convert to the expected format
    const result: FileBasedStream['qualities'] = {};
    Object.entries(qualityMap).forEach(([quality, data]) => {
      const validQuality = getValidQualityFromString(quality);
      result[validQuality] = data;
    });

    return result;
  } catch (error) {
    console.error('Error parsing video links:', error);
    throw new NotFoundError('Failed to parse video links');
  }
}

function extractTitleAndYear(input: string) {
  const regex = /^(.*?),.*?(\d{4})/;
  const match = input.match(regex);

  if (match) {
    const title = match[1];
    const year = match[2];
    return { title: title.trim(), year: year ? parseInt(year, 10) : null };
  }
  return null;
}

export { extractTitleAndYear, parseSubtitleLinks, parseVideoLinks, generateRandomFavs };
