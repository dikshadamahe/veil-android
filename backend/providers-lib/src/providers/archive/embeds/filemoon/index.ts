import { unpack } from 'unpacker';

import { flags } from '@/entrypoint/utils/targets';
import { makeEmbed } from '@/providers/base';
import { Caption, getCaptionTypeFromUrl, labelToLanguageCode } from '@/providers/captions';

import type { SubtitleResult } from './types';

const M3U8_REGEX = /https?:\/\/[^\s"'<>]+\.m3u8[^\s"'<>]*/gi;

function extractScripts(html: string): string[] {
  const out: string[] = [];
  const re = /<script[^>]*>([\s\S]*?)<\/script>/gi;
  let m: RegExpExecArray | null;
  // eslint-disable-next-line no-cond-assign
  while ((m = re.exec(html))) {
    out.push(m[1] ?? '');
  }
  return out;
}

function unpackIfPacked(script: string): string | null {
  try {
    if (script.includes('eval(function(p,a,c,k,e,d)')) {
      const once = unpack(script);
      if (once && once !== script) return once;
      // try one more time in case of double-pack
      const twice = unpack(once ?? script);
      return twice ?? once ?? null;
    }
  } catch {
    // ignore
  }
  return null;
}

function extractAllM3u8(text: string): string[] {
  const seen: Record<string, true> = {};
  const urls: string[] = [];
  const body = text ?? '';
  const unescaped = body
    .replace(/\\x([0-9a-fA-F]{2})/g, (_s, h) => String.fromCharCode(parseInt(h, 16)))
    .replace(/\\u([0-9a-fA-F]{4})/g, (_s, h) => String.fromCharCode(parseInt(h, 16)));
  const matches = unescaped.match(M3U8_REGEX) ?? [];
  for (const u of matches) {
    if (!seen[u]) {
      seen[u] = true;
      urls.push(u);
    }
  }
  return urls;
}

export const fileMoonScraper = makeEmbed({
  id: 'filemoon',
  name: 'Filemoon',
  rank: 405,
  flags: [flags.IP_LOCKED],
  async scrape(ctx) {
    // Load initial page
    const page = await ctx.proxiedFetcher.full<string>(ctx.url, {
      headers: { Referer: ctx.url },
    });
    const pageHtml = page.body;

    // Prefer iframe payload
    const iframeMatch = /<iframe[^>]+src=["']([^"']+)["']/i.exec(pageHtml);
    const iframeUrl = iframeMatch ? new URL(iframeMatch[1], page.finalUrl || ctx.url).toString() : null;

    const payloadResp = iframeUrl
      ? await ctx.proxiedFetcher.full<string>(iframeUrl, { headers: { Referer: page.finalUrl || ctx.url } })
      : page;
    const payloadHtml = payloadResp.body;

    // Try unpacking packed JS
    const scripts = extractScripts(payloadHtml);
    let collected = payloadHtml;
    for (const s of scripts) {
      const unpacked = unpackIfPacked(s);
      if (unpacked) collected += `\n${unpacked}`;
    }

    // Extract m3u8s
    const m3u8s = extractAllM3u8(collected);
    if (m3u8s.length === 0) throw new Error('Filemoon: no m3u8 found');

    // Captions (optional)
    const captions: Caption[] = [];
    try {
      const u = new URL(ctx.url);
      const subtitlesLink = u.searchParams.get('sub.info');
      if (subtitlesLink) {
        const res = await ctx.proxiedFetcher<SubtitleResult>(subtitlesLink);
        for (const c of res) {
          const language = labelToLanguageCode(c.label);
          const type = getCaptionTypeFromUrl(c.file);
          if (!language || !type) continue;
          captions.push({ id: c.file, url: c.file, type, language, hasCorsRestrictions: false });
        }
      }
    } catch {
      // ignore caption errors
    }

    return {
      stream: [
        {
          id: 'primary',
          type: 'hls',
          playlist: m3u8s[0],
          flags: [flags.IP_LOCKED],
          captions,
        },
      ],
    };
  },
});
