import { MovieScrapeContext, ShowScrapeContext } from '@/utils/context';

import { getAddonStreams, parseStreamData } from './helpers';
import { DebridParsedStream, debridProviders } from './types';

export async function getCometStreams(
  token: string,
  debridProvider: debridProviders,
  ctx: MovieScrapeContext | ShowScrapeContext,
): Promise<DebridParsedStream[]> {
  const cometBaseUrl = 'https://comet.elfhosted.com'; // Free instance sponsored by ElfHosted, but you can customize it to your liking.
  // If you're unfamiliar with Stremio addons, basically stremio addons are just api endpoints, and so they have to encode the config in the url to be able to have a config that works with stremio
  // So this just constructs the user's config for Comet. It could be customized to your liking as well!
  const cometConfig = btoa(
    JSON.stringify({
      maxResultsPerResolution: 0,
      maxSize: 0,
      cachedOnly: false,
      removeTrash: true,
      resultFormat: ['all'],
      debridService: debridProvider,
      debridApiKey: token,
      debridStreamProxyPassword: '',
      languages: { exclude: [], preferred: ['en'] },
      resolutions: {},
      options: { remove_ranks_under: -10000000000, allow_english_in_languages: false, remove_unknown_languages: false },
    }),
  );

  const cometStreamsRaw = (await getAddonStreams(`${cometBaseUrl}/${cometConfig}`, ctx)).streams;
  const newStreams: { title: string; url: string }[] = [];

  for (let i = 0; i < cometStreamsRaw.length; i++) {
    if (cometStreamsRaw[i].description !== undefined)
      newStreams.push({
        title: (cometStreamsRaw[i].description as string).replace(/\n/g, ''),
        url: cometStreamsRaw[i].url,
      });
  }
  const parsedData = await parseStreamData(newStreams, ctx);
  return parsedData;
}
