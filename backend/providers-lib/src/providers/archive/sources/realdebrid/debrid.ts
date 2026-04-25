/* eslint-disable no-console */
import { MovieScrapeContext, ShowScrapeContext } from '@/utils/context';
import { NotFoundError } from '@/utils/errors';

interface RealDebridUnrestrictResponse {
  id: string;
  filename: string;
  mimeType: string;
  filesize: number;
  link: string;
  host: string;
  chunks: number;
  download: string;
  streamable: number;
}

interface RealDebridTorrentResponse {
  id: string;
  filename: string;
  hash: string;
  bytes: number;
  host: string;
  split: number;
  progress: number;
  status: string;
  added: string;
  files?: Array<{
    id: number;
    path: string;
    bytes: number;
    selected: number;
  }>;
  links?: string[];
}

const REALDEBRID_BASE_URL = 'https://api.real-debrid.com/rest/1.0';

// Add a magnet link to RealDebrid
async function addMagnetToRealDebrid(
  magnetUrl: string,
  token: string,
  ctx: MovieScrapeContext | ShowScrapeContext,
): Promise<string> {
  console.log('Adding magnet to RealDebrid:', `${magnetUrl.substring(0, 50)}...`);

  const data = await ctx.proxiedFetcher.full(`${REALDEBRID_BASE_URL}/torrents/addMagnet`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: `magnet=${encodeURIComponent(magnetUrl)}`,
  });

  if (data.statusCode !== 201 || !data.body.id) {
    throw new NotFoundError('Failed to add magnet to RealDebrid');
  }

  console.log('Magnet added successfully, torrent ID:', data.body.id);
  return data.body.id;
}

// Select all files in a torrent
async function selectAllFiles(
  torrentId: string,
  token: string,
  ctx: MovieScrapeContext | ShowScrapeContext,
): Promise<void> {
  console.log('Selecting all files for torrent:', torrentId);

  const data = await ctx.proxiedFetcher.full(`${REALDEBRID_BASE_URL}/torrents/selectFiles/${torrentId}`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: 'files=all',
  });

  if (data.statusCode !== 204 && data.statusCode !== 202) {
    throw new NotFoundError('Failed to select all files for torrent');
  }

  console.log('All files selected successfully for torrent:', torrentId);
}

// Select specific file in a torrent
async function selectSpecificFile(
  torrentId: string,
  fileId: number,
  token: string,
  ctx: MovieScrapeContext | ShowScrapeContext,
): Promise<void> {
  console.log(`Selecting specific file (${fileId}) for torrent:`, torrentId);

  const data = await ctx.proxiedFetcher.full(`${REALDEBRID_BASE_URL}/torrents/selectFiles/${torrentId}`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: `files=${fileId}`,
  });

  // Success cases: 204 (No Content) or 202 (Already Done)
  if (data.statusCode !== 204 && data.statusCode !== 202) {
    throw new Error(`Unexpected status code: ${data.statusCode}`);
  }

  console.log(`File ${fileId} selected successfully for torrent:`, torrentId);
}

// Get torrent info from RealDebrid
async function getTorrentInfo(
  torrentId: string,
  token: string,
  ctx: MovieScrapeContext | ShowScrapeContext,
): Promise<RealDebridTorrentResponse> {
  const data = await ctx.proxiedFetcher.full<RealDebridTorrentResponse>(
    `${REALDEBRID_BASE_URL}/torrents/info/${torrentId}`,
    {
      method: 'GET',
      headers: {
        Authorization: `Bearer ${token}`,
      },
    },
  );

  if (data.statusCode === 401 || data.statusCode === 403) {
    throw new NotFoundError('Failed to get torrent info');
  }

  return data.body;
}

// Unrestrict a link on RealDebrid
async function unrestrictLink(
  link: string,
  token: string,
  ctx: MovieScrapeContext | ShowScrapeContext,
): Promise<RealDebridUnrestrictResponse> {
  console.log('Unrestricting link:', `${link.substring(0, 50)}...`);

  const data = await ctx.proxiedFetcher.full<RealDebridUnrestrictResponse>(`${REALDEBRID_BASE_URL}/unrestrict/link`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: `link=${encodeURIComponent(link)}`,
  });

  if (data.statusCode === 401 || data.statusCode === 403 || !data.body) {
    throw new NotFoundError('Failed to unrestrict link');
  }

  console.log('Link unrestricted successfully, got download URL');
  return data.body;
}

// Process a magnet link through RealDebrid and get streaming URLs
export async function getUnrestrictedLink(
  magnetUrl: string,
  token: string,
  ctx: MovieScrapeContext | ShowScrapeContext,
): Promise<string> {
  try {
    if (!magnetUrl || !magnetUrl.startsWith('magnet:?')) {
      throw new NotFoundError(`Invalid magnet URL: ${magnetUrl}`);
    }

    // Add the magnet to RealDebrid
    const torrentId = await addMagnetToRealDebrid(magnetUrl, token, ctx);
    console.log('Torrent added to RealDebrid:', torrentId);

    // Get initial torrent info
    let torrentInfo = await getTorrentInfo(torrentId, token, ctx);
    // console.log('Torrent info:', torrentInfo);
    let waitAttempts = 0;
    const maxWaitAttempts = 5;

    // First wait until the torrent is ready for file selection or another actionable state
    while (waitAttempts < maxWaitAttempts) {
      console.log(
        `Initial torrent status (wait attempt ${waitAttempts + 1}/${maxWaitAttempts}): ${torrentInfo.status}, progress: ${torrentInfo.progress}%`,
      );

      // If the torrent is ready for file selection or already being processed, break
      if (
        torrentInfo.status === 'waiting_files_selection' ||
        torrentInfo.status === 'downloaded' ||
        torrentInfo.status === 'downloading'
      ) {
        break;
      }

      // Check for error states
      const errorStatuses = ['error', 'virus', 'dead', 'magnet_error', 'magnet_conversion'];
      if (errorStatuses.includes(torrentInfo.status)) {
        throw new NotFoundError(`Torrent processing failed with status: ${torrentInfo.status}`);
      }

      // Wait 2 seconds before checking again
      await new Promise<void>((resolve) => {
        setTimeout(resolve, 2000);
      });
      waitAttempts++;

      // Get updated torrent info
      torrentInfo = await getTorrentInfo(torrentId, token, ctx);
      // console.log('Torrent info attempt 2:', torrentInfo);
    }

    // Select files based on status
    if (torrentInfo.status === 'waiting_files_selection') {
      // If we have files info, try to select the best MP4 file
      if (torrentInfo.files && torrentInfo.files.length > 0) {
        const mp4Files = torrentInfo.files.filter((file) => file.path.toLowerCase().endsWith('.mp4'));

        if (mp4Files.length > 0) {
          console.log(`Found ${mp4Files.length} MP4 files, attempting to match title`);
          const cleanMediaTitle = ctx.media.title.toLowerCase();
          const firstWord = cleanMediaTitle.split(' ')[0];

          // Try exact title match first
          const exactMatches = mp4Files.filter((file) => {
            const cleanFileName = file.path.split('/').pop()?.toLowerCase().replace(/\./g, ' ') || '';
            return cleanFileName.includes(cleanMediaTitle);
          });

          let selectedFile;
          if (exactMatches.length > 0) {
            console.log(`Found ${exactMatches.length} files exactly matching title "${ctx.media.title}"`);
            selectedFile = exactMatches.reduce((largest, current) =>
              current.bytes > largest.bytes ? current : largest,
            );
          } else {
            // Try matching first word
            const firstWordMatches = mp4Files.filter((file) => {
              return file.path.includes(firstWord);
            });

            if (firstWordMatches.length > 0) {
              console.log(`Found ${firstWordMatches.length} files matching first word "${firstWord}"`);
              selectedFile = firstWordMatches.reduce((largest, current) =>
                current.bytes > largest.bytes ? current : largest,
              );
            } else {
              // If no matching files, select the largest MP4
              console.log(`No matching files found, selecting largest MP4`);
              selectedFile = mp4Files.reduce((largest, current) => (current.bytes > largest.bytes ? current : largest));
            }
          }
          const largestMp4 = selectedFile;

          // Select only this specific file
          await selectSpecificFile(torrentId, largestMp4.id, token, ctx);
          console.log('Selected specific file:', largestMp4.id);
        } else {
          // If no MP4 files, select all files
          await selectAllFiles(torrentId, token, ctx);
          console.log('Selected all files');
        }
      } else {
        // If no file info available, select all files
        await selectAllFiles(torrentId, token, ctx);
        console.log('Selected all files');
      }
    } else if (torrentInfo.status !== 'downloaded') {
      // For any other non-completed status, select all files
      await selectAllFiles(torrentId, token, ctx);
      console.log('Selected all files');
    }

    // Wait for the torrent to be processed
    let attempts = 0;
    const maxAttempts = 30; // 60 seconds max wait time (2s * 30)
    const validCompletedStatuses = ['downloaded', 'ready'];
    const errorStatuses = ['error', 'virus', 'dead', 'magnet_error', 'magnet_conversion'];

    console.log('Waiting for torrent to be processed...');

    while (attempts < maxAttempts) {
      torrentInfo = await getTorrentInfo(torrentId, token, ctx);
      console.log(
        `Torrent status (attempt ${attempts + 1}/${maxAttempts}): ${torrentInfo.status}, progress: ${torrentInfo.progress}%`,
      );

      // Check if torrent is ready
      if (validCompletedStatuses.includes(torrentInfo.status) && torrentInfo.links && torrentInfo.links.length > 0) {
        let targetLink = torrentInfo.links[0];

        // If there are files, try to find the largest MP4
        if (torrentInfo.files) {
          const mp4Files = torrentInfo.files.filter(
            (file) => file.path.toLowerCase().endsWith('.mp4') && file.selected === 1,
          );

          if (mp4Files.length > 0) {
            console.log(`Found ${mp4Files.length} MP4 files, selecting largest`);
            const largestMp4 = mp4Files.reduce((largest, current) =>
              current.bytes > largest.bytes ? current : largest,
            );

            const linkIndex = torrentInfo.files.findIndex((f) => f.id === largestMp4.id);
            if (linkIndex !== -1 && torrentInfo.links[linkIndex]) {
              targetLink = torrentInfo.links[linkIndex];
              console.log(`Selected largest MP4: ${largestMp4.path}, size: ${largestMp4.bytes} bytes`);
            }
          } else {
            console.log('No MP4 files found, using first available link');
          }
        }

        // Unrestrict the link
        const unrestrictedData = await unrestrictLink(targetLink, token, ctx);
        return unrestrictedData.download;
      }

      // Check for error states
      if (errorStatuses.includes(torrentInfo.status)) {
        throw new NotFoundError(`Torrent processing failed with status: ${torrentInfo.status}`);
      }

      // If torrent is stuck in downloading with 0% progress for a while, try to re-select files
      if (torrentInfo.status === 'downloading' && torrentInfo.progress === 0 && attempts > 5 && attempts % 5 === 0) {
        console.log('Torrent seems stuck at 0%, trying to re-select files...');

        // Get fresh torrent info
        torrentInfo = await getTorrentInfo(torrentId, token, ctx);

        if (torrentInfo.files && torrentInfo.files.length > 0) {
          const mp4Files = torrentInfo.files.filter((file) => file.path.toLowerCase().endsWith('.mp4'));

          if (mp4Files.length > 0) {
            const largestMp4 = mp4Files.reduce((largest, current) =>
              current.bytes > largest.bytes ? current : largest,
            );

            // Re-select this specific file
            await selectSpecificFile(torrentId, largestMp4.id, token, ctx);
          } else {
            // If no MP4 files, re-select all files
            await selectAllFiles(torrentId, token, ctx);
          }
        } else {
          // If no file info available, re-select all files
          await selectAllFiles(torrentId, token, ctx);
        }
      }

      // Special case: if we have reached 100% progress but status isn't "downloaded" yet
      if (torrentInfo.progress === 100 && attempts > 10) {
        console.log('Torrent is at 100% but status is not completed. Checking for links anyway...');
        if (torrentInfo.links && torrentInfo.links.length > 0) {
          const unrestrictedData = await unrestrictLink(torrentInfo.links[0], token, ctx);
          return unrestrictedData.download;
        }
      }

      // Wait 2 seconds before checking again
      // eslint-disable-next-line no-await-in-loop
      await new Promise((resolve) => {
        setTimeout(resolve, 2000);
      });
      attempts++;
    }

    throw new NotFoundError(`Timeout waiting for torrent to be processed after ${maxAttempts * 2} seconds`);
  } catch (error: unknown) {
    if (error instanceof NotFoundError) throw error;
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';
    throw new NotFoundError(`Error processing magnet link: ${errorMessage}`);
  }
}
