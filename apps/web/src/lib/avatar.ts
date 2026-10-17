const MAX_AVATAR_BYTES = 512 * 1024;
const AVATAR_TYPES = ["image/png", "image/jpeg", "image/webp"];

export function readAvatar(file: File): Promise<string> {
  if (!AVATAR_TYPES.includes(file.type)) {
    return Promise.reject(new Error("Choose a PNG, JPEG, or WebP image."));
  }
  if (file.size > MAX_AVATAR_BYTES) {
    return Promise.reject(new Error("Choose an image up to 512 KB."));
  }
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      if (typeof reader.result === "string") resolve(reader.result);
      else reject(new Error("Could not read the image. Please try again."));
    };
    reader.onerror = reader.onabort = () =>
      reject(new Error("Could not read the image. Please try again."));
    reader.readAsDataURL(file);
  });
}
