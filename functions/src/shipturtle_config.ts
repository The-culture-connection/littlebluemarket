import {
  SHIPTURTLE_API_KEY,
  SHIPTURTLE_AUTH_HEADER,
  SHIPTURTLE_BASE_URL,
  SHIPTURTLE_VENDORS_PATH,
} from './config.ts';

/**
 * The Shipturtle merchant API's key, host and header style, read once per
 * call so a missing secret degrades to "not configured" instead of a throw.
 * Shared by the roster, the vendor directory and the orders sync. Nothing
 * here ever logs the token.
 */
export function shipturtleConfig(): { key: string; base: string; path: string; header: string } {
  let key = '';
  try {
    key = SHIPTURTLE_API_KEY.value();
  } catch {
    key = '';
  }
  return {
    key,
    base: SHIPTURTLE_BASE_URL.value().replace(/\/$/, ''),
    path: SHIPTURTLE_VENDORS_PATH.value().trim(),
    header: SHIPTURTLE_AUTH_HEADER.value() || 'Authorization',
  };
}

export function authHeaders(key: string, style: string): Record<string, string> {
  switch (style.trim().toLowerCase()) {
    case 'x-api-key':
      return { 'x-api-key': key };
    case 'access-token':
      return { 'access-token': key };
    default:
      return { Authorization: `Bearer ${key}` };
  }
}
