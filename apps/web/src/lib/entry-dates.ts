const MINUTE = 60_000;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;
/** Older than this, a date reads better as a calendar date than as "5 weeks ago". */
const RELATIVE_LIMIT = 30 * DAY;

/**
 * How long ago a moment was: "just now", "5 minutes ago", "yesterday", "3 days ago". Past
 * 30 days it is a calendar date, without the year when it is this year.
 */
export function formatWhen(iso: string, now = Date.now(), locale?: string) {
  const then = new Date(iso);
  const age = Math.max(0, now - then.getTime());
  if (age < MINUTE) return "just now";

  if (age < RELATIVE_LIMIT) {
    const relative = new Intl.RelativeTimeFormat(locale, { numeric: "auto" });
    if (age < HOUR) return relative.format(-Math.floor(age / MINUTE), "minute");
    if (age < DAY) return relative.format(-Math.floor(age / HOUR), "hour");
    return relative.format(-Math.floor(age / DAY), "day");
  }

  const sameYear = then.getFullYear() === new Date(now).getFullYear();
  return then.toLocaleDateString(locale, {
    day: "numeric",
    month: "short",
    ...(!sameYear && { year: "numeric" }),
  });
}

/** The exact moment, for a tooltip. */
export const formatExactly = (iso: string, locale?: string) =>
  new Date(iso).toLocaleString(locale, {
    dateStyle: "long",
    timeStyle: "short",
  });
