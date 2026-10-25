import { useRef, useState } from "react";
import { ImageIcon, TrashIcon, UploadIcon } from "lucide-react";
import { useQuery, useQueryClient } from "@tanstack/react-query";

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

  if (!imageId && !canManage) return null;

  return (
    <div className="space-y-2">
      <div className="flex aspect-square w-full items-center justify-center overflow-hidden rounded-2xl border bg-muted/40">
        {imageId && url.data ? (
          <img
            id="entry-image"
            src={url.data}
            alt={`Image of ${name}`}
            className="size-full object-cover"
          />
        ) : (
          <ImageIcon
            aria-hidden="true"
            className="size-10 text-muted-foreground"
          />
        )}
      </div>
      {canManage && (
        <div className="flex flex-wrap gap-2">
          <input
            ref={input}
            id="entry-image-input"
            type="file"
            accept="image/*"
            className="sr-only"
            aria-label="Upload an image"
            onChange={event => {
              const file = event.target.files?.[0];
              if (file) void upload(file);
            }}
          />
          <Button
            id="entry-image-upload"
            variant="outline"
            size="sm"
            isLoading={uploading}
            disabled={uploading || disabled}
            onClick={() => input.current?.click()}
          >
            <UploadIcon aria-hidden="true" data-icon="inline-start" />
            {imageId ? "Replace" : "Add an image"}
          </Button>
          {imageId && (
            <Button
              id="entry-image-remove"
              variant="ghost"
              size="sm"
              disabled={uploading || disabled}
              onClick={() => onChange(null)}
            >
              <TrashIcon aria-hidden="true" data-icon="inline-start" />
              Remove
            </Button>
          )}
        </div>
      )}
      {error && (
        <Alert id="entry-image-error" variant="destructive">
          <AlertDescription>{error}</AlertDescription>
        </Alert>
      )}
    </div>
  );
}
