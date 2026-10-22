export const IMAGE_REF_PREFIX = "atlas-image:";
export const MAX_IMAGE_BYTES = 25 * 1024 * 1024;

/** Uploads one image and returns the reference the document stores. Never a URL. */
export async function uploadImage(options: {
  file: File;
  csrfToken: string | undefined;
  fetchImpl?: typeof fetch;
}): Promise<string> {
  const { file, csrfToken, fetchImpl = fetch } = options;
  if (!csrfToken)
    throw new Error("Your session expired. Reload the page and try again.");
  if (file.size > MAX_IMAGE_BYTES)
    throw new Error("The image is larger than 25 MB.");

  const body = new FormData();
  body.append("file", file);
  const response = await fetchImpl("/api/images", {
    method: "POST",
    credentials: "same-origin",
    cache: "no-store",
    headers: { Accept: "application/json", "x-csrf-token": csrfToken },
    body,
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok || typeof data.id !== "string")
    throw new Error(data.error ?? "Could not upload the image.");
  return IMAGE_REF_PREFIX + data.id;
}

/**
 * Resolves stored image references to signed URLs. Signed URLs expire, so each one is cached
 * only for part of its lifetime and then requested again.
 */
export function createImageResolver(options: {
  fetchUrl: (imageId: string) => Promise<string>;
  ttlMs?: number;
  now?: () => number;
}) {
  const { fetchUrl, ttlMs = 8 * 60 * 1000, now = Date.now } = options;
  const cache = new Map<string, { url: Promise<string>; expires: number }>();

  function resolve(reference: string): Promise<string> {
    if (!reference.startsWith(IMAGE_REF_PREFIX))
      return Promise.resolve(reference);
    const id = reference.slice(IMAGE_REF_PREFIX.length);
    const hit = cache.get(id);
    if (hit && hit.expires > now()) return hit.url;

    const url = fetchUrl(id);
    cache.set(id, { url, expires: now() + ttlMs });
    url.catch(() => cache.delete(id));
    return url;
  }

  /** Answers a reference with a local URL, so a fresh upload shows without a round trip. */
  resolve.prime = (reference: string, url: string) =>
    cache.set(reference.slice(IMAGE_REF_PREFIX.length), {
      url: Promise.resolve(url),
      expires: now() + ttlMs,
    });

  return resolve;
}
