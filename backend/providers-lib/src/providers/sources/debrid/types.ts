// these need to be the names that correspond with Torrentio's
export type debridProviders = 'torbox' | 'real-debrid';

export interface stremioStream {
  name: string;
  description?: string;
  title?: string;
  url: string;
  infoHash: string;
  fileIdx: number;
  behaviorHints?: {
    bingeGroup: string;
    filename: string;
    videoSize?: number;
    videoHash?: string;
  };
  sources?: string[];
}

export type stremioAddonStreamResponse = Promise<{ streams: stremioStream[]; [key: string]: any }>;

export type torrentioResponse = Awaited<stremioAddonStreamResponse> & {
  cacheMaxAge: number;
  staleRevalidate: number;
  staleError: number;
};

export type DebridParsedStream = {
  resolution?: string;
  year?: number;
  source?: string;
  bitDepth?: string;
  codec?: string;
  audio?: string;
  container?: string;
  seasons?: number[];
  season?: number;
  episodes?: number[];
  episode?: number;
  complete?: boolean;
  unrated?: boolean;
  remastered?: boolean;
  languages?: string[];
  dubbed?: boolean;
  title: string;
  url: string;
};
