import { load } from 'cheerio';

import { flags } from '@/entrypoint/utils/targets';
import { makeEmbed } from '@/providers/base';
import { EmbedScrapeContext } from '@/utils/context';
import { NotFoundError } from '@/utils/errors';
import { createM3U8ProxyUrl } from '@/utils/proxy';

export const streambucketScraper = makeEmbed({
  id: 'streambucket',
  name: 'Streambucket',
  rank: 220,
  disabled: true,
  flags: [flags.CORS_ALLOWED],
  async scrape(ctx: EmbedScrapeContext) {
    // Handle redirects for multiembed/streambucket URLs
    let baseUrl = ctx.url;
    if (baseUrl.includes('multiembed') || baseUrl.includes('ghostplayer')) {
      const redirectResp = await ctx.proxiedFetcher.full(baseUrl);
      baseUrl = redirectResp.finalUrl;
    }

    const userAgent =
      'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Mobile Safari/537.36';

    ctx.progress(20);

    // Prepare POST data for requesting the page
    const data = {
      'button-click': 'ZEhKMVpTLVF0LVBTLVF0LVAtMGs1TFMtUXpPREF0TC0wLVYzTi0wVS1RTi0wQTFORGN6TmprLTU=',
      'button-referer': '',
    };

    // Send POST request to fetch initial response
    const postResp = await ctx.proxiedFetcher<string>(baseUrl, {
      method: 'POST',
      body: new URLSearchParams(data),
      headers: {
        Referer: 'https://multiembed.mov',
        'X-Requested-With': 'XMLHttpRequest',
        'User-Agent': userAgent,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
    });

    ctx.progress(40);

    // Extract the session token required to fetch sources
    const tokenMatch = postResp.match(/load_sources\("([^"]+)"\)/);
    if (!tokenMatch) throw new NotFoundError('Session token not found');
    const token = tokenMatch[1];

    // Request the sources list using the extracted token
    const sourcesResp = await ctx.proxiedFetcher<string>('https://streamingnow.mov/response.php', {
      method: 'POST',
      body: new URLSearchParams({ token }),
      headers: {
        Referer: baseUrl,
        'X-Requested-With': 'XMLHttpRequest',
        'User-Agent': userAgent,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
    });

    ctx.progress(60);

    const $ = load(sourcesResp);

    // Try to find VIP source first, then fallback to other sources
    let selectedSource = $('li')
      .filter((_, el) => {
        const text = $(el).text().toLowerCase();
        return text.includes('vipstream-s');
      })
      .first();

    // If no VIP, try other high-quality sources
    if (!selectedSource.length) {
      // Try vidsrc first as fallback
      selectedSource = $('li')
        .filter((_, el) => {
          const text = $(el).text().toLowerCase();
          return text.includes('vidsrc');
        })
        .first();

      // If no vidsrc, try any stream source
      if (!selectedSource.length) {
        selectedSource = $('li').first();
      }
    }

    if (!selectedSource.length) {
      throw new NotFoundError('No streams available');
    }

    // Extract server and video IDs from the selected source element
    const serverId = selectedSource.attr('data-server');
    const videoId = selectedSource.attr('data-id');

    if (!serverId || !videoId) {
      throw new NotFoundError('Server or video ID not found');
    }

    ctx.progress(70);

    // Fetch VIP streaming page HTML
    const vipUrl = `https://streamingnow.mov/playvideo.php?video_id=${videoId}&server_id=${serverId}&token=${token}&init=1`;
    const vipResp = await ctx.proxiedFetcher<string>(vipUrl, {
      headers: {
        Referer: baseUrl,
        'User-Agent': userAgent,
      },
    });

    ctx.progress(80);

    // Check if response contains CAPTCHA (anti-bot protection)
    const hasCaptcha =
      vipResp.includes('captcha') || vipResp.includes('Verification') || vipResp.includes('Select all images');

    if (hasCaptcha) {
      throw new NotFoundError('Stream protected by CAPTCHA');
    }

    // Look for direct video file URL in the response
    const directVideoMatch =
      vipResp.match(/file:"(https?:\/\/[^"]+)"/) ||
      vipResp.match(/"(https?:\/\/[^"]+\.m3u8[^"]*)"/) ||
      vipResp.match(/"(https?:\/\/[^"]+\.mp4[^"]*)"/);
    if (directVideoMatch) {
      const videoUrl = directVideoMatch[1];

      // Extract domain for referer
      const urlObj = new URL(baseUrl);
      const defaultDomain = `${urlObj.protocol}//${urlObj.host}`;

      const headers = {
        Referer: defaultDomain,
        'User-Agent': userAgent,
      };

      return {
        stream: [
          {
            id: 'primary',
            type: 'hls',
            playlist: createM3U8ProxyUrl(videoUrl, { requires: [flags.CORS_ALLOWED], disallowed: [] }, headers),
            headers,
            flags: [flags.CORS_ALLOWED],
            captions: [],
          },
        ],
      };
    }

    // Fallback to iframe method
    const vip$ = load(vipResp);
    const iframe = vip$('iframe.source-frame.show');
    if (!iframe.length) throw new NotFoundError('Video iframe not found');

    const iframeUrl = iframe.attr('src');
    if (!iframeUrl) throw new NotFoundError('Iframe URL not found');

    // Get video page
    const videoResp = await ctx.proxiedFetcher<string>(iframeUrl, {
      headers: {
        Referer: vipUrl,
        'User-Agent': userAgent,
      },
    });

    ctx.progress(90);

    // Extract video URL
    const videoMatch = videoResp.match(/file:"(https?:\/\/[^"]+)"/);
    if (!videoMatch) throw new NotFoundError('Video URL not found');

    const videoUrl = videoMatch[1];

    // Extract domain for referer
    const urlObj = new URL(baseUrl);
    const defaultDomain = `${urlObj.protocol}//${urlObj.host}`;

    const headers = {
      Referer: defaultDomain,
      'User-Agent': userAgent,
    };

    return {
      stream: [
        {
          id: 'primary',
          type: 'hls',
          playlist: createM3U8ProxyUrl(videoUrl, { requires: [flags.CORS_ALLOWED], disallowed: [] }, headers),
          headers,
          flags: [flags.CORS_ALLOWED],
          captions: [],
        },
      ],
    };
  },
});
