// import { alphaScraper, deltaScraper } from '@/providers/embeds/nsbx';
// import { astraScraper, novaScraper, orionScraper } from '@/providers/embeds/whvx';
import { bombtheirishScraper } from '@/providers/archive/sources/bombtheirish';
import { streamtapeScraper } from '@/providers/embeds/streamtape';
import { warezcdnembedMp4Scraper } from '@/providers/embeds/warezcdn/mp4';
import { Stream } from '@/providers/streams';
import { IndividualEmbedRunnerOptions } from '@/runners/individualRunner';
import { ProviderRunnerOptions } from '@/runners/runner';

const SKIP_VALIDATION_CHECK_IDS = [
  warezcdnembedMp4Scraper.id,
  streamtapeScraper.id,
  // deltaScraper.id,
  // alphaScraper.id,
  // novaScraper.id,
  // astraScraper.id,
  // orionScraper.id,
];

const UNPROXIED_VALIDATION_CHECK_IDS = [
  // sources here are always proxied, so we dont need to validate with a proxy
  bombtheirishScraper.id, // this one is dead, but i'll keep it here for now
];

export function isValidStream(stream: Stream | undefined): boolean {
  if (!stream) return false;
  if (stream.type === 'hls') {
    if (!stream.playlist) return false;
    return true;
  }
  if (stream.type === 'file') {
    const validQualities = Object.values(stream.qualities).filter((v) => v.url.length > 0);
    if (validQualities.length === 0) return false;
    return true;
  }

  // unknown file type
  return false;
}

/**
 * Check if a URL is a proxy URL that should be validated with normal fetch
 * instead of proxiedFetcher
 */
function isAlreadyProxyUrl(url: string): boolean {
  return url.includes('/m3u8-proxy?url=') || url.includes('shegu.net');
}

/**
 * Check if a response result indicates an invalid/error response that should fail validation
 */
function isErrorResponse(result: { statusCode: number; body: string | any; finalUrl?: string }): boolean {
  if (result.statusCode === 403) return true;

  const bodyStr = typeof result.body === 'string' ? result.body : String(result.body);
  if (result.statusCode === 200 && bodyStr.trim() === 'error_wrong_ip') return true;

  if (result.statusCode === 200) {
    try {
      const parsed = JSON.parse(bodyStr);
      if (parsed.status === 403 && parsed.msg === 'Access Denied') return true;
    } catch {
      // Not JSON, continue
    }
  }

  return false;
}

export async function validatePlayableStream(
  stream: Stream,
  ops: ProviderRunnerOptions | IndividualEmbedRunnerOptions,
  sourcererId: string,
): Promise<Stream | null> {
  if (SKIP_VALIDATION_CHECK_IDS.includes(sourcererId)) return stream;
  if (stream.skipValidation) return stream;

  const alwaysUseNormalFetch = UNPROXIED_VALIDATION_CHECK_IDS.includes(sourcererId);

  if (stream.type === 'hls') {
    // dirty temp fix for base64 urls to prep for fmhy poll
    if (stream.playlist.startsWith('data:')) return stream;

    const useNormalFetch = alwaysUseNormalFetch || isAlreadyProxyUrl(stream.playlist);

    let result;
    if (useNormalFetch) {
      try {
        const response = await fetch(stream.playlist, {
          method: 'GET',
          headers: {
            ...stream.preferredHeaders,
            ...stream.headers,
          },
          signal: AbortSignal.timeout(20000),
        });
        result = {
          statusCode: response.status,
          body: await response.text(),
          finalUrl: response.url,
        };
      } catch (error) {
        return null;
      }
    } else {
      try {
        result = await Promise.race([
          ops.proxiedFetcher.full(stream.playlist, {
            method: 'GET',
            headers: {
              ...stream.preferredHeaders,
              ...stream.headers,
            },
          }),
          new Promise<never>((_, reject) => {
            setTimeout(() => reject(new Error('Timeout')), 20000);
          }),
        ]);
      } catch {
        return null;
      }
    }

    if (result.statusCode < 200 || result.statusCode >= 400 || isErrorResponse(result)) return null;
    return stream;
  }

  if (stream.type === 'file') {
    const validQualitiesResults = await Promise.all(
      Object.values(stream.qualities).map(async (quality) => {
        const useNormalFetch = alwaysUseNormalFetch || isAlreadyProxyUrl(quality.url);

        if (useNormalFetch) {
          try {
            const response = await fetch(quality.url, {
              method: 'GET',
              headers: {
                ...stream.preferredHeaders,
                ...stream.headers,
                Range: 'bytes=0-1',
              },
              signal: AbortSignal.timeout(20000),
            });
            return {
              statusCode: response.status,
              body: await response.text(),
              finalUrl: response.url,
            };
          } catch (error) {
            return { statusCode: 500, body: '', finalUrl: quality.url };
          }
        }

        try {
          return await Promise.race([
            ops.proxiedFetcher.full(quality.url, {
              method: 'GET',
              headers: {
                ...stream.preferredHeaders,
                ...stream.headers,
                Range: 'bytes=0-1',
              },
            }),
            new Promise<never>((_, reject) => {
              setTimeout(() => reject(new Error('Timeout')), 20000);
            }),
          ]);
        } catch {
          return { statusCode: 500, body: '', finalUrl: quality.url };
        }
      }),
    );
    // remove invalid qualities from the stream
    const validQualities = stream.qualities;
    Object.keys(stream.qualities).forEach((quality, index) => {
      if (
        validQualitiesResults[index].statusCode < 200 ||
        validQualitiesResults[index].statusCode >= 400 ||
        isErrorResponse(validQualitiesResults[index])
      ) {
        delete validQualities[quality as keyof typeof stream.qualities];
      }
    });

    if (Object.keys(validQualities).length === 0) return null;
    return { ...stream, qualities: validQualities };
  }

  return null;
}

export async function validatePlayableStreams(
  streams: Stream[],
  ops: ProviderRunnerOptions | IndividualEmbedRunnerOptions,
  sourcererId: string,
): Promise<Stream[]> {
  if (SKIP_VALIDATION_CHECK_IDS.includes(sourcererId)) return streams;

  return (await Promise.all(streams.map((stream) => validatePlayableStream(stream, ops, sourcererId)))).filter(
    (v) => v !== null,
  ) as Stream[];
}
