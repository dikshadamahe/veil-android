/**
 * Browser detection utilities
 */

export function detectBrowser(): 'chrome' | 'firefox' | 'safari' | 'unknown' {
  // Check if we're in a browser environment
  if (typeof navigator === 'undefined') {
    return 'unknown';
  }

  const userAgent = navigator.userAgent.toLowerCase();

  // Detect Chrome/Brave (Brave includes "Chrome" in its user agent)
  if (userAgent.includes('chrome') && !userAgent.includes('edg')) {
    return 'chrome';
  }

  // Detect Firefox
  if (userAgent.includes('firefox')) {
    return 'firefox';
  }

  // Detect Safari
  if (userAgent.includes('safari') && !userAgent.includes('chrome')) {
    return 'safari';
  }

  return 'unknown';
}

export function isChromeOrBrave(): boolean {
  return detectBrowser() === 'chrome';
}

export function isFirefox(): boolean {
  return detectBrowser() === 'firefox';
}

export function isSafari(): boolean {
  return detectBrowser() === 'safari';
}
