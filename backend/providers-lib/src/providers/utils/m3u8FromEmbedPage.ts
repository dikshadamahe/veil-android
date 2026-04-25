import { load } from 'cheerio';

import { UseableFetcher } from '@/fetchers/types';
import { NotFoundError } from '@/utils/errors';

const M3U8_RE = /(https?:\/\/[^\s"'\\<>]+?\.m3u8[^\s"'\\<>]*)/gi;

/**
 * Best-effort: pull the first m3u8 URL from raw HTML/JS, or from a one-level nested iframe.
 */
function firstM3u8InText(text: string): string | null {
  M3U8_RE.lastIndex = 0;
  const m = M3U8_RE.exec(text);
  return m?.[1] ?? null;
}

export type PullM3u8FromPageOptions = {
  proxiedFetcher: UseableFetcher;
  pageUrl: string;
  referer: string;
  userAgent: string;
};

/**
 * Fetches an embed page and tries to find a playable HLS URL.
 */
export async function pullM3u8FromEmbedPage(opts: PullM3u8FromPageOptions): Promise<string> {
  const { proxiedFetcher, pageUrl, referer, userAgent } = opts;

  const baseHeaders: Record<string, string> = {
    'User-Agent': userAgent,
    Referer: referer,
    Accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
  };

  const first = await proxiedFetcher.full<string>(pageUrl, { headers: baseHeaders });
  const body = typeof first.body === 'string' ? first.body : String(first.body ?? '');
  const finalUrl = first.finalUrl ?? pageUrl;

  const direct = firstM3u8InText(body);
  if (direct) {
    return direct;
  }

  const $ = load(body);
  const iframeSrc = $('iframe[src], frame[src]').first().attr('src');
  if (iframeSrc) {
    try {
      const resolved = new URL(iframeSrc, finalUrl).href;
      const second = await proxiedFetcher.full<string>(resolved, {
        headers: {
          ...baseHeaders,
          Referer: finalUrl,
        },
      });
      const inner = typeof second.body === 'string' ? second.body : String(second.body ?? '');
      const nested = firstM3u8InText(inner);
      if (nested) {
        return nested;
      }
    } catch {
      // ignore nested fetch failure
    }
  }

  throw new NotFoundError('No m3u8 found in embed page');
}
