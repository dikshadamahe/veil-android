import { PackerParams } from './types';

export function rtt(str: string) {
  return str.replace(/[a-z]/gi, (c) => {
    return String.fromCharCode(c.charCodeAt(0) + (c.toLowerCase() < 'n' ? 13 : -13));
  });
}

export function decodeAtom(e: string) {
  const t = atob(e.split('').reverse().join(''));
  let o = '';
  for (let i = 0; i < t.length; i++) {
    const r = 'K9L'[i % 3];
    const n = t.charCodeAt(i) - ((r.charCodeAt(0) % 5) + 1);
    o += String.fromCharCode(n);
  }
  return atob(o);
}

export function extractPackerParams(rawInput: string): PackerParams | null {
  const regex = /'((?:[^'\\]|\\.)*)',\s*(\d+),\s*(\d+),\s*'((?:[^'\\]|\\.)*)'\.split\('\|'\)/;

  const match = regex.exec(rawInput);

  if (!match) {
    console.error('Could not parse parameters. Format is not as expected.');
    return null;
  }

  return {
    payload: match[1],
    radix: parseInt(match[2], 10),
    count: parseInt(match[3], 10),
    keywords: match[4].split('|'),
  };
}

export function decodeDeanEdwards(params: PackerParams): string {
  const { payload, radix, count, keywords } = params;

  const dict: { [key: string]: string } = Object.create(null);

  const encodeBase = (num: number): string => {
    if (num < radix) {
      const char = num % radix;
      return char > 35 ? String.fromCharCode(char + 29) : char.toString(36);
    }

    const prefix = encodeBase(Math.floor(num / radix));

    const char = num % radix;
    const suffix = char > 35 ? String.fromCharCode(char + 29) : char.toString(36);

    return prefix + suffix;
  };

  let i = count;
  while (i--) {
    const key = encodeBase(i);
    const value = keywords[i] || key;
    dict[key] = value;
  }

  return payload.replace(/\b\w+\b/g, (word) => {
    if (word in dict) {
      return dict[word];
    }
    return word;
  });
}

export function decodeHex(str: string): string {
  return str.replace(/\\x([0-9A-Fa-f]{2})/g, (_match, hexGroup) => {
    return String.fromCharCode(parseInt(hexGroup, 16));
  });
}

export function unescapeString(str: string) {
  return str.replace(/\\(.)/g, (match, char) => char);
}
