import { MovieMedia, ShowMedia } from '@/entrypoint/utils/media';
import { FeatureMap } from '@/entrypoint/utils/targets';
import { UseableFetcher } from '@/fetchers/types';

export type ScrapeContext = {
  proxiedFetcher: UseableFetcher;
  fetcher: UseableFetcher;
  progress(val: number): void;
  features: FeatureMap;
};

export type EmbedInput = {
  url: string;
};

export type EmbedScrapeContext = EmbedInput & ScrapeContext;

export type MovieScrapeContext = ScrapeContext & {
  media: MovieMedia;
};

export type ShowScrapeContext = ScrapeContext & {
  media: ShowMedia;
};
