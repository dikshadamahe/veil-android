import { MovieMedia, ShowMedia } from '@/entrypoint/utils/media';
import { ScrapeContext } from '@/utils/context';

type JikanAnime = {
  mal_id: number;
  type?: string;
  title?: string;
  title_english?: string | null;
  titles?: Array<{ title: string; type: string }>;
  year?: number | null;
  aired?: {
    prop?: { from?: { year?: number | null } };
  };
};

type JikanSearchResponse = {
  data: JikanAnime[];
};

const cache = new Map<string, number>();

function normalizeTitle(t: string) {
  return t
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

function guessYear(a: JikanAnime): number | null {
  return (typeof a.year === 'number' ? a.year : null) ?? a.aired?.prop?.from?.year ?? null;
}

function matchesType(mediaType: 'show' | 'movie', t?: string) {
  if (!t) return true; // be lenient
  const jt = t.toLowerCase();
  return mediaType === 'show' ? jt === 'tv' : jt === 'movie';
}

export async function getMalIdFromMedia(ctx: ScrapeContext, media: MovieMedia | ShowMedia): Promise<number> {
  const key = `${media.type}:${media.title}:${media.releaseYear}`;
  const cached = cache.get(key);
  if (cached) return cached;

  const q = media.title;
  // Jikan search
  const res = await ctx.proxiedFetcher<JikanSearchResponse>('/anime', {
    baseUrl: 'https://api.jikan.moe/v4',
    query: {
      q,
      // Jikan expects tv|movie etc; provide a hint but still filter manually
      type: media.type === 'show' ? 'tv' : 'movie',
      sfw: 'true',
      limit: '20',
      order_by: 'popularity',
      sort: 'asc',
    },
  });

  const items = Array.isArray(res?.data) ? res.data : [];
  if (!items.length) {
    throw new Error('MAL id not found');
  }

  const targetTitle = normalizeTitle(media.title);

  // Score results by title similarity and year closeness
  const scored = items
    .filter((it) => matchesType(media.type, it.type))
    .map((it) => {
      const titles: string[] = [it.title || ''];
      if (it.title_english) titles.push(it.title_english);
      if (Array.isArray(it.titles)) titles.push(...it.titles.map((t) => t.title));
      const normTitles = titles.map(normalizeTitle).filter(Boolean);
      const exact = normTitles.includes(targetTitle);
      const partial = normTitles.some((t) => t.includes(targetTitle) || targetTitle.includes(t));
      const y = guessYear(it);
      const yearDelta = typeof y === 'number' ? Math.abs(y - media.releaseYear) : 5; // unknown year => penalize
      let score = 0;
      if (exact) score += 100;
      else if (partial) score += 50;
      score += Math.max(0, 20 - yearDelta * 4);
      return { it, score };
    })
    .sort((a, b) => b.score - a.score);

  const winner = scored[0]?.it ?? items[0];
  const malId = winner?.mal_id;
  if (!malId) throw new Error('MAL id not found');

  cache.set(key, malId);
  return malId;
}
