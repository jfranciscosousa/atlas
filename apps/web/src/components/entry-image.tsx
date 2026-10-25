import { useRef, useState } from "react";
import { CameraIcon, ImageIcon, ImagePlusIcon, TrashIcon } from "lucide-react";
import { useQuery, useQueryClient } from "@tanstack/react-query";

import { Spinner } from "./ui/spinner";
import { Button } from "./ui/button";
import { Alert, AlertDescription } from "./ui/alert";
import { IMAGE_REF_PREFIX, uploadImage } from "../lib/images";
import { fetchImageUrl } from "../hooks/use-campaigns";

// A signed URL lasts a few minutes, so the cache keeps it for less than that.
const URL_TTL_MS = 8 * 60 * 1000;

/** The portrait or cover of an entry. The GM may upload or remove it. */
export function EntryImage({
  imageId,
  name,
  canManage,
  onChange,
  disabled = false,
}: {
  imageId: string | null;
  name: string;
  canManage: boolean;
  onChange: (imageId: string | null) => void;
  disabled?: boolean;
}) {
  const queryClient = useQueryClient();
  const meta = () => queryClient.getDefaultOptions().mutations?.meta;
  const input = useRef<HTMLInputElement>(null);
  const [error, setError] = useState<string>();
  const [uploading, setUploading] = useState(false);
  const url = useQuery({
    queryKey: ["entry-image", imageId],
    queryFn: () => fetchImageUrl(meta(), imageId!),
    enabled: !!imageId,
    staleTime: URL_TTL_MS,
    retry: false,
  });

  async function upload(file: File) {
    setError(undefined);
    setUploading(true);
    try {
      const reference = await uploadImage({
        file,
        csrfToken: meta()?.csrfToken,
      });
      onChange(reference.slice(IMAGE_REF_PREFIX.length));
    } catch (failure) {
      setError(
        failure instanceof Error ? failure.message : "Could not upload."
      );
    } finally {
      setUploading(false);
      if (input.current) input.current.value = "";
    }
  }

  const pickFile = () => input.current?.click();

  if (!imageId && !canManage) return null;

  return (
    <div className="w-full space-y-2">
      <input
        ref={input}
        id="entry-image-input"
        type="file"
        accept="image/*"
        className="sr-only"
        aria-label="Upload an image"
        disabled={uploading || disabled}
        onChange={event => {
          const file = event.target.files?.[0];
          if (file) void upload(file);
        }}
      />
      {imageId ? (
        <div className="relative aspect-square w-full overflow-hidden rounded-2xl border bg-muted/40">
          {url.data ? (
            <img
              id="entry-image"
              src={url.data}
              alt={`Image of ${name}`}
              className="size-full object-cover"
            />
          ) : (
            <div className="flex size-full items-center justify-center">
              {url.isError ? (
                <ImageIcon
                  aria-hidden="true"
                  className="size-10 text-muted-foreground"
                />
              ) : (
                <Spinner />
              )}
            </div>
          )}
          {uploading && (
            <div className="absolute inset-0 flex items-center justify-center bg-background/60">
              <Spinner />
            </div>
          )}
          {canManage && (
            <div className="absolute right-2 bottom-2 flex gap-1">
              <Button
                id="entry-image-replace"
                type="button"
                variant="secondary"
                size="icon-xs"
                className="rounded-full shadow-xs"
                aria-label={`Replace image of ${name}`}
                disabled={uploading || disabled}
                onClick={pickFile}
              >
                <CameraIcon aria-hidden="true" />
              </Button>
              <Button
                id="entry-image-remove"
                type="button"
                variant="secondary"
                size="icon-xs"
                className="rounded-full shadow-xs"
                aria-label={`Remove image of ${name}`}
                disabled={uploading || disabled}
                onClick={() => onChange(null)}
              >
                <TrashIcon aria-hidden="true" />
              </Button>
            </div>
          )}
        </div>
      ) : (
        canManage && (
          <>
            <Button
              id="entry-image-upload"
              type="button"
              variant="outline"
              size="sm"
              className="w-fit border-dashed text-muted-foreground hover:text-foreground"
              isLoading={uploading}
              disabled={uploading || disabled}
              onClick={pickFile}
              aria-label={`Upload an image of ${name}`}
              aria-describedby="entry-image-help"
            >
              <ImagePlusIcon aria-hidden="true" data-icon="inline-start" />
              Add image
            </Button>
            <span id="entry-image-help" className="sr-only">
              PNG, JPEG, or WebP, up to 25 MB.
            </span>
          </>
        )
      )}
      {error && (
        <Alert id="entry-image-error" variant="destructive">
          <AlertDescription>{error}</AlertDescription>
        </Alert>
      )}
    </div>
  );
}
