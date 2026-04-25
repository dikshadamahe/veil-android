import { Flags } from '@/entrypoint/utils/targets';
import { Stream } from '@/providers/streams';
import { EmbedScrapeContext, MovieScrapeContext, ShowScrapeContext } from '@/utils/context';

export type MediaScraperTypes = 'show' | 'movie';

export type SourcererEmbed = {
  embedId: string;
  url: string;
};

export type SourcererOutput = {
  embeds: SourcererEmbed[];
  stream?: Stream[];
};

export type SourcererOptions = {
  id: string;
  name: string; // displayed in the UI
  rank: number; // the higher the number, the earlier it gets put on the queue
  disabled?: boolean;
  // these sources are built in but not used by default
  // this can have many uses, we use this for sources that only work on official instances
  externalSource?: boolean;
  flags: Flags[];
  scrapeMovie?: (input: MovieScrapeContext) => Promise<SourcererOutput>;
  scrapeShow?: (input: ShowScrapeContext) => Promise<SourcererOutput>;
};

export type Sourcerer = SourcererOptions & {
  type: 'source';
  disabled: boolean;
  externalSource: boolean;
  mediaTypes: MediaScraperTypes[];
};

export function makeSourcerer(state: SourcererOptions): Sourcerer {
  const mediaTypes: MediaScraperTypes[] = [];
  if (state.scrapeMovie) mediaTypes.push('movie');
  if (state.scrapeShow) mediaTypes.push('show');
  return {
    ...state,
    type: 'source',
    disabled: state.disabled ?? false,
    externalSource: state.externalSource ?? false,
    mediaTypes,
  };
}

export type EmbedOutput = {
  stream: Stream[];
};

export type EmbedOptions = {
  id: string;
  name: string; // displayed in the UI
  rank: number; // the higher the number, the earlier it gets put on the queue
  disabled?: boolean;
  flags: Flags[];
  scrape: (input: EmbedScrapeContext) => Promise<EmbedOutput>;
};

export type Embed = EmbedOptions & {
  type: 'embed';
  disabled: boolean;
  mediaTypes: undefined;
};

export function makeEmbed(state: EmbedOptions): Embed {
  return {
    ...state,
    type: 'embed',
    disabled: state.disabled ?? false,
    mediaTypes: undefined,
  };
}
