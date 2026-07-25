const isoDateTimePattern = /^(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2}:\d{2})(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/;

/** ISO 8601日時を画面表示用のYYYY-MM-DD HH:mm:ssへ変換する。 */
export function formatDateTime(value: string | null): string {
  if (!value) {
    return '-';
  }
  const match = isoDateTimePattern.exec(value);
  return match ? `${match[1]} ${match[2]}` : value;
}
