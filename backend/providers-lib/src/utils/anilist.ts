import { MovieMedia, ShowMedia } from '@/entrypoint/utils/media';
import { ScrapeContext } from '@/utils/context';

type AnilistMedia = {
  id: number;
  type: 'ANIME' | 'MANGA';
  format: 'TV' | 'TV_SHORT' | 'MOVIE' | 'SPECIAL' | 'OVA' | 'ONA' | 'MUSIC' | 'MANGA' | 'NOVEL' | 'ONE_SHOT';
  seasonYear?: number;
  title: {
    romaji: string;
    english?: string;
    native?: string;
  };
};

type AnilistSearchResponse = {
  data: {
    Page: {
      media: AnilistMedia[];
    };
  };
};

const cache = new Map<string, number>();

function normalizeTitle(t: string) {
  return t
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

function matchesType(mediaType: 'show' | 'movie', anilist: AnilistMedia) {
  if (mediaType === 'show') {
    return ['TV', 'TV_SHORT', 'OVA', 'ONA', 'SPECIAL'].includes(anilist.format);
  }
  return anilist.format === 'MOVIE';
}

const anilistQuery = `
query ($search: String, $type: MediaType) {
  Page(page: 1, perPage: 20) {
    media(search: $search, type: $type, sort: POPULARITY_DESC) {
      id
      type
      format
      seasonYear
      title {
        romaji
        english
        native
      }
    }
  }
}
`;

export async function getAnilistIdFromMedia(ctx: ScrapeContext, media: MovieMedia | ShowMedia): Promise<number> {
  const key = `${media.type}:${media.title}:${media.releaseYear}`;
  const cached = cache.get(key);
  if (cached) return cached;

  const res = await ctx.proxiedFetcher<AnilistSearchResponse>('', {
    baseUrl: 'https://graphql.anilist.co',
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Accept: 'application/json',
    },
    body: JSON.stringify({
      query: anilistQuery,
      variables: {
        search: media.title,
        type: 'ANIME',
      },
    }),
  });

  const items = res.data?.Page?.media ?? [];
  if (!items.length) {
    throw new Error('AniList id not found');
  }

  const targetTitle = normalizeTitle(media.title);

  const scored = items
    .filter((it) => matchesType(media.type, it))
    .map((it) => {
      const titles: string[] = [it.title.romaji];
      if (it.title.english) titles.push(it.title.english);
      if (it.title.native) titles.push(it.title.native);
      const normTitles = titles.map(normalizeTitle).filter(Boolean);
      const exact = normTitles.includes(targetTitle);
      const partial = normTitles.some((t) => t.includes(targetTitle) || targetTitle.includes(t));
      const yearDelta = it.seasonYear ? Math.abs(it.seasonYear - media.releaseYear) : 5;
      let score = 0;
      if (exact) score += 100;
      else if (partial) score += 50;
      score += Math.max(0, 20 - yearDelta * 4);
      return { it, score };
    })
    .sort((a, b) => b.score - a.score);

  const winner = scored[0]?.it ?? items[0];
  const anilistId = winner?.id;
  if (!anilistId) throw new Error('AniList id not found');

  cache.set(key, anilistId);
  return anilistId;
}
const anilistTitlesQuery = `
query ($id: Int) {
  Media(id: $id, type: ANIME) {
    title {
      romaji
      english
      native
    }
    synonyms
  }
}
`;

type AnilistTitlesResponse = {
  data: {
    Media: {
      title: {
        romaji: string;
        english?: string;
        native?: string;
      };
      synonyms: string[];
    };
  };
};

export async function getAnilistTitles(ctx: ScrapeContext, media: MovieMedia | ShowMedia): Promise<string[]> {
  const id = await getAnilistIdFromMedia(ctx, media);
  const res = await ctx.proxiedFetcher<AnilistTitlesResponse>('', {
    baseUrl: 'https://graphql.anilist.co',
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Accept: 'application/json',
    },
    body: JSON.stringify({
      query: anilistTitlesQuery,
      variables: {
        id,
      },
    }),
  });

  const titles = [
    res.data.Media.title.romaji,
    res.data.Media.title.english,
    res.data.Media.title.native,
    ...res.data.Media.synonyms,
  ]
    .filter((t): t is string => !!t)
    .map((t) => t.toLowerCase());

  return titles;
}

export async function getAnilistEnglishTitle(
  ctx: ScrapeContext,
  media: MovieMedia | ShowMedia,
): Promise<string | null> {
  const id = await getAnilistIdFromMedia(ctx, media);
  const res = await ctx.proxiedFetcher<AnilistTitlesResponse>('', {
    baseUrl: 'https://graphql.anilist.co',
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Accept: 'application/json',
    },
    body: JSON.stringify({
      query: anilistTitlesQuery,
      variables: {
        id,
      },
    }),
  });

  const englishTitle = res.data.Media.title.english;

  return englishTitle ? englishTitle.toLowerCase() : null;
}
