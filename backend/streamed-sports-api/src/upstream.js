const { URL } = require('url');

/**
 * Fetch JSON (or binary) from streamed.pk with timeout + basic error shaping.
 */
async function fetchUpstream(baseUrl, pathWithQuery, { timeoutMs, accept }) {
  const url = new URL(pathWithQuery, baseUrl).toString();
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const res = await fetch(url, {
      method: 'GET',
      signal: controller.signal,
      headers: {
        Accept: accept || 'application/json',
        'User-Agent': 'veil-streamed-sports/1.0',
      },
    });

    const contentType = res.headers.get('content-type') || '';
    if (!res.ok) {
      const bodyText = await res.text().catch(() => '');
      const err = new Error(`Upstream ${res.status} for ${pathWithQuery}`);
      err.status = res.status;
      err.upstreamBody = bodyText.slice(0, 500);
      throw err;
    }

    if (accept && accept !== 'application/json') {
      const buffer = Buffer.from(await res.arrayBuffer());
      return { contentType, buffer };
    }

    if (contentType.includes('application/json')) {
      return { contentType, json: await res.json() };
    }

    // streamed.pk sometimes returns JSON without a precise content-type
    const text = await res.text();
    try {
      return { contentType: contentType || 'application/json', json: JSON.parse(text) };
    } catch {
      return { contentType: contentType || 'text/plain', text };
    }
  } catch (err) {
    if (err.name === 'AbortError') {
      const timeoutErr = new Error(`Upstream timeout after ${timeoutMs}ms`);
      timeoutErr.status = 504;
      throw timeoutErr;
    }
    throw err;
  } finally {
    clearTimeout(timer);
  }
}

module.exports = { fetchUpstream };
