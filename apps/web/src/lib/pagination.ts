/** Rows on one page of a list. */
export const PAGE_SIZE = 25;

export function pageCount(total: number, size = PAGE_SIZE) {
  return Math.max(1, Math.ceil(total / size));
}

/** The nearest page that exists. A stale link to a page that is gone shows the last page. */
export function clampPage(page: number, total: number, size = PAGE_SIZE) {
  return Math.min(Math.max(1, page), pageCount(total, size));
}

export function pageSlice<T>(items: T[], page: number, size = PAGE_SIZE) {
  const start = (clampPage(page, items.length, size) - 1) * size;
  return items.slice(start, start + size);
}

/** The page in a URL. Page 1 and anything that is not a whole number above 1 give no page. */
export function parsePage(value: unknown) {
  const page =
    typeof value === "number"
      ? value
      : typeof value === "string" && /^\d+$/.test(value)
        ? Number(value)
        : NaN;
  return Number.isSafeInteger(page) && page > 1 ? page : undefined;
}
