import { parse, stringify } from 'hls-parser';
import { MasterPlaylist } from 'hls-parser/types';

import { UseableFetcher } from '@/fetchers/types';

export async function convertPlaylistsToDataUrls(
  fetcher: UseableFetcher,
  playlistUrl: string,
  headers?: Record<string, string>,
) {
  const playlistData = await fetcher(playlistUrl, { headers });
  const playlist = parse(playlistData);

  if (playlist.isMasterPlaylist) {
    // Extract base URL from the playlist URL for resolving relative variant URLs
    const baseUrl = new URL(playlistUrl).origin;

    await Promise.all(
      (playlist as MasterPlaylist).variants.map(async (variant) => {
        // Resolve relative URLs against the base URL
        let variantUrl = variant.uri;
        if (!variantUrl.startsWith('http')) {
          // Handle relative URLs - add leading slash if it doesn't exist
          if (!variantUrl.startsWith('/')) {
            variantUrl = `/${variantUrl}`;
          }
          variantUrl = baseUrl + variantUrl;
        }

        const variantPlaylistData = await fetcher(variantUrl, { headers });
        const variantPlaylist = parse(variantPlaylistData);
        variant.uri = `data:application/vnd.apple.mpegurl;base64,${btoa(stringify(variantPlaylist))}`;
      }),
    );
  }

  return `data:application/vnd.apple.mpegurl;base64,${btoa(stringify(playlist))}`;
}
