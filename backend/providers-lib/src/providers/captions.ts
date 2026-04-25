import ISO6391 from 'iso-639-1';

export const captionTypes = {
  srt: 'srt',
  vtt: 'vtt',
};
export type CaptionType = keyof typeof captionTypes;

export type Caption = {
  type: CaptionType;
  id: string; // only unique per stream
  opensubtitles?: boolean;
  url: string;
  hasCorsRestrictions: boolean;
  language: string;
  // Optional fields provided by Wyzie
  flagUrl?: string;
  display?: string;
  media?: string;
  isHearingImpaired?: boolean;
  source?: string;
  encoding?: string;
};

export function getCaptionTypeFromUrl(url: string): CaptionType | null {
  const extensions = Object.keys(captionTypes) as CaptionType[];
  const type = extensions.find((v) => url.endsWith(`.${v}`));
  if (!type) return null;
  return type;
}

export function labelToLanguageCode(label: string): string | null {
  // extra language codes
  const languageMap: Record<string, string> = {
    'chinese - hong kong': 'zh',
    'chinese - traditional': 'zh',
    czech: 'cs',
    danish: 'da',
    dutch: 'nl',
    english: 'en',
    'english - sdh': 'en',
    finnish: 'fi',
    french: 'fr',
    german: 'de',
    greek: 'el',
    hungarian: 'hu',
    italian: 'it',
    korean: 'ko',
    norwegian: 'no',
    polish: 'pl',
    portuguese: 'pt',
    'portuguese - brazilian': 'pt',
    romanian: 'ro',
    'spanish - european': 'es',
    'spanish - latin american': 'es',
    spanish: 'es',
    swedish: 'sv',
    turkish: 'tr',
    اَلْعَرَبِيَّةُ: 'ar',
    বাংলা: 'bn',
    filipino: 'tl',
    indonesia: 'id',
    اردو: 'ur',
    English: 'en',
    Arabic: 'ar',
    Bosnian: 'bs',
    Bulgarian: 'bg',
    Croatian: 'hr',
    Czech: 'cs',
    Danish: 'da',
    Dutch: 'nl',
    Estonian: 'et',
    Finnish: 'fi',
    French: 'fr',
    German: 'de',
    Greek: 'el',
    Hebrew: 'he',
    Hungarian: 'hu',
    Indonesian: 'id',
    Italian: 'it',
    Norwegian: 'no',
    Persian: 'fa',
    'farsi/persian': 'fa',
    Polish: 'pl',
    Portuguese: 'pt',
    'Protuguese (BR)': 'pt-br',
    Romanian: 'ro',
    Russian: 'ru',
    russian: 'ru',
    Serbian: 'sr',
    Slovenian: 'sl',
    Spanish: 'es',
    Swedish: 'sv',
    Thai: 'th',
    Turkish: 'tr',
    // Simple language codes
    ng: 'en',
    re: 'fr',
    pa: 'es',
  };

  // First try our mapping
  const mappedCode = languageMap[label.toLowerCase()];
  if (mappedCode) return mappedCode;

  // Fallback to ISO6391 library
  const code = ISO6391.getCode(label);
  if (code.length === 0) return null;
  return code;
}

export function isValidLanguageCode(code: string | null): boolean {
  if (!code) return false;
  return ISO6391.validate(code);
}

export function removeDuplicatedLanguages(list: Caption[]) {
  const beenSeen: Record<string, true> = {};

  return list.filter((sub) => {
    if (beenSeen[sub.language]) return false;
    beenSeen[sub.language] = true;
    return true;
  });
}
