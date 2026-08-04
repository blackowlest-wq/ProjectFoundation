/**
 * 認証済み画面向けメッセージカタログAPI。
 */
import { getJson } from './apiClient';

export const DEFAULT_MESSAGE_LOCALE = 'ja-JP';

export type MessageCatalogResponse = {
  locale: string;
  messages: Record<string, string>;
};

export function fetchMessageCatalog(locale = DEFAULT_MESSAGE_LOCALE): Promise<MessageCatalogResponse> {
  return getJson<MessageCatalogResponse>(`/api/master/messages?locale=${encodeURIComponent(locale)}`);
}
