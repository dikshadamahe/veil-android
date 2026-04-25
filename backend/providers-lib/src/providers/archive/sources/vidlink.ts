// /* eslint-disable no-console */
// import { flags } from '@/entrypoint/utils/targets';
// import { Caption, labelToLanguageCode } from '@/providers/captions';
// import { MovieScrapeContext, ShowScrapeContext } from '@/utils/context';
// import { NotFoundError } from '@/utils/errors';

// import { SourcererOutput, makeSourcerer } from '../base';

// async function comboScraper(ctx: MovieScrapeContext | ShowScrapeContext): Promise<SourcererOutput> {
//   const embedUrl =
//     ctx.media.type === 'movie'
//       ? `https://vidlink.pro/movie/${ctx.media.tmdbId}`
//       : `https://vidlink.pro/tv/${ctx.media.tmdbId}/${ctx.media.season.number}/${ctx.media.episode.number}`;

//   const apiResponse = await ctx.proxiedFetcher<{
//     results: Array<{
//       video_urls: string[];
//       subtitles: Array<{ label: string; file: string }>;
//     }>;
//   }>('https://psvl.api.pstream.org/api/video-url', {
//     query: { embedUrl },
//   });

//   if (!apiResponse?.results?.length) throw new NotFoundError('No results found');
//   const primaryResult = apiResponse.results[0];

//   if (!primaryResult.video_urls?.length) throw new NotFoundError('No video URLs found');

//   const captions: Caption[] = [];
//   for (const sub of primaryResult.subtitles) {
//     const language = labelToLanguageCode(sub.label.split('-')[0].trim());
//     if (!language) continue;

//     captions.push({
//       id: sub.file,
//       url: sub.file,
//       type: 'vtt',
//       hasCorsRestrictions: false,
//       language,
//     });
//   }

//   return {
//     embeds: [],
//     stream: [
//       {
//         id: 'primary',
//         playlist: primaryResult.video_urls[0],
//         type: 'hls',
//         flags: [flags.CORS_ALLOWED],
//         captions,
//       },
//     ],
//   };
// }

// export const vidlinkScraper = makeSourcerer({
//   id: 'vidlink',
//   name: 'PSVL',
//   rank: 113,
//   disabled: true,
//   flags: [flags.CORS_ALLOWED],
//   scrapeMovie: comboScraper,
//   scrapeShow: comboScraper,
// });
