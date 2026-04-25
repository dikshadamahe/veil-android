import { ShowMedia } from '@/entrypoint/utils/media';
import { ScrapeContext } from '@/utils/context';

const GEMINI_BASE_URL = 'https://gemini.aether.mom/v1beta/models/gemini-2.5-flash-lite:generateContent';

type MyanimeSearchResult = {
  id: string;
  title: string;
  alt_title: string;
  tvInfo: {
    showType: string;
    totalEpisodes: number;
    poster: string;
    year: number;
    sub: number;
    dub: number;
    eps: number;
  };
};

type GeminiResponse = {
  results: Array<{
    id: string;
    season?: number;
  }>;
};

function buildPrompt(media: ShowMedia, searchResults: MyanimeSearchResult[]): string {
  const seasons = media.season.number > 1 ? ` and has ${media.season.number} seasons` : '';
  const prompt = `
    You are an AI that matches TMDB movie and show data to myanime search results.
    The user is searching for "${media.title}" which was released in ${media.releaseYear}${seasons}.
    The user is looking for season ${media.season.number} (TMDB title: "${media.season.title}", ${
      media.season.episodeCount ?? 'unknown'
    } episodes), episode ${media.episode.number}.

    Here are the search results from myanime:
    ${JSON.stringify(searchResults, null, 2)}

    IMPORTANT: Some shows on TMDB have continuous episode numbering across seasons (e.g., episode 25 is the first episode of season 2), but myanime lists seasons as separate entries with their own episode counts. The myanime entry may also have a different title (e.g., "Mugen Train Arc").
    To solve this, please return a JSON object with a "results" array that contains ALL entries from the search results that match the requested show, including all of its seasons, even if the user is only asking for one.
    Each object in the "results" array should have the "id" of the matching anime from the myanime search results, and the "season" number. You must determine the season number for each entry based on its title.
    The results MUST be sorted by season number in ascending order so the calling code can correctly map the episode number.
    Pay close attention to the season title and episode counts from both TMDB and the myanime results to find the best match. If TMDB combines seasons into one, you must split them based on the episode counts in the search results.
    Use the TMDB season title as the primary key for matching, and do not assign the same season number to different arcs.
    Your response must only be the raw JSON object, without any markdown formatting, comments, or other text.
  `;
  return prompt.trim();
}

export async function getAiMatching(
  ctx: ScrapeContext,
  media: ShowMedia,
  searchResults: MyanimeSearchResult[],
): Promise<GeminiResponse | null> {
  try {
    const prompt = buildPrompt(media, searchResults);
    const response = await ctx.fetcher<any>(GEMINI_BASE_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }],
      }),
    });

    const text = response.candidates[0].content.parts[0].text;
    const firstBracket = text.indexOf('{');
    const lastBracket = text.lastIndexOf('}');
    if (firstBracket === -1 || lastBracket === -1) {
      throw new Error('Invalid AI response: No JSON object found');
    }
    const jsonString = text.substring(firstBracket, lastBracket + 1);
    const data = JSON.parse(jsonString) as GeminiResponse;

    if (!data.results || !Array.isArray(data.results)) {
      throw new Error('Invalid AI response format');
    }

    return data;
  } catch (error) {
    if (error instanceof Error) {
      ctx.progress(0); // Reset progress on error
    }
    return null;
  }
}
