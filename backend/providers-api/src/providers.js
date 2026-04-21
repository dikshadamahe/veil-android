import { makeProviders, makeStandardFetcher, targets } from "@p-stream/providers";

export const providers = makeProviders({
  fetcher: makeStandardFetcher(fetch),
  target: targets.NATIVE,
});
