import { useRef, useState } from "react";
import { CameraIcon, ImagePlusIcon, TrashIcon } from "lucide-react";
import { useForm } from "@tanstack/react-form";

import { Input } from "./ui/input";
import { Field, FieldLabel, FieldDescription } from "./ui/field";
import { Button } from "./ui/button";
import { Avatar, AvatarImage, AvatarFallback } from "./ui/avatar";
import { Alert, AlertDescription } from "./ui/alert";
import { readAvatar } from "../lib/avatar";
import { useProfile, useProfileUpdate } from "../hooks/use-profile";

export function ProfileForm({ userId }: { userId: string }) {
  const { data: profile } = useProfile(userId);
  const update = useProfileUpdate(userId);
  const [fileError, setFileError] = useState("");
  const [reading, setReading] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);
  const form = useForm({
    defaultValues: {
      displayName: profile.displayName ?? "",
      avatar: profile.avatar,
    },
    onSubmit: async ({ value }) => {
      try {
        const saved = await update.mutateAsync(value);
        form.reset({
          displayName: saved.displayName ?? "",
          avatar: saved.avatar,
        });
      } catch {
        // Keep unsaved changes so the user can retry.
      }
    },
  });
  const busy = reading || update.isPending;
  const error = fileError || update.error?.message;

  return (
    <form
      id="profile-form"
      className="space-y-6"
      aria-busy={busy}
      onSubmit={event => {
        event.preventDefault();
        if (!busy && !fileError) void form.handleSubmit();
      }}
    >
      <form.Field name="avatar">
        {field => {
          const hasImage = Boolean(field.state.value);
          const pickFile = () => inputRef.current?.click();
          return (
            <Field>
              <FieldLabel>Profile photo</FieldLabel>
              <div className="flex flex-wrap items-center gap-4">
                <input
                  ref={inputRef}
                  id="profile-avatar"
                  type="file"
                  className="sr-only"
                  accept="image/png,image/jpeg,image/webp"
                  aria-label="Upload a profile photo"
                  disabled={busy}
                  onChange={async event => {
                    const file = event.target.files?.[0];
                    event.target.value = "";
                    if (!file) return;
                    update.reset();
                    setFileError("");
                    setReading(true);
                    try {
                      field.handleChange(await readAvatar(file));
                    } catch (error) {
                      setFileError(
                        error instanceof Error
                          ? error.message
                          : "Could not read the image."
                      );
                    } finally {
                      setReading(false);
                    }
                  }}
                />
                {hasImage ? (
                  <div className="relative">
                    <Avatar className="size-24">
                      <AvatarImage
                        id="profile-avatar-preview"
                        src={field.state.value ?? undefined}
                        alt="Your profile photo"
                      />
                      <AvatarFallback
                        role="img"
                        aria-label="Your profile photo"
                        className="text-3xl font-semibold"
                      >
                        {profile.displayName.slice(0, 1).toUpperCase()}
                      </AvatarFallback>
                    </Avatar>
                    <div className="absolute -right-1.5 -bottom-1.5 flex gap-1">
                      <Button
                        id="profile-avatar-replace"
                        type="button"
                        variant="secondary"
                        size="icon-xs"
                        className="rounded-full shadow-xs"
                        aria-label="Replace photo"
                        disabled={busy}
                        onClick={pickFile}
                      >
                        <CameraIcon aria-hidden="true" />
                      </Button>
                      <Button
                        id="profile-avatar-remove"
                        type="button"
                        variant="secondary"
                        size="icon-xs"
                        className="rounded-full shadow-xs"
                        aria-label="Remove photo"
                        disabled={busy}
                        onClick={() => {
                          field.handleChange(null);
                          setFileError("");
                          update.reset();
                        }}
                      >
                        <TrashIcon aria-hidden="true" />
                      </Button>
                    </div>
                  </div>
                ) : (
                  <button
                    id="profile-avatar-empty"
                    type="button"
                    disabled={busy}
                    onClick={pickFile}
                    className="group/upload flex size-24 shrink-0 cursor-pointer flex-col items-center justify-center gap-1.5 rounded-full border-2 border-dashed border-border text-muted-foreground transition-colors outline-none hover:border-primary/60 hover:text-primary focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/30 disabled:pointer-events-none disabled:opacity-50"
                    aria-label="Upload a profile photo"
                  >
                    <ImagePlusIcon
                      aria-hidden="true"
                      className="size-6 transition-transform group-hover/upload:scale-110"
                    />
                    <span className="px-2 text-xs font-medium">
                      Upload photo
                    </span>
                  </button>
                )}
                <div className="min-w-0 flex-1">
                  {hasImage ? (
                    <FieldDescription id="profile-avatar-help">
                      PNG, JPEG, or WebP. Up to 512 KB.
                    </FieldDescription>
                  ) : (
                    <FieldDescription id="profile-avatar-help">
                      Add a photo so others can recognize you. PNG, JPEG, or
                      WebP, up to 512 KB.
                    </FieldDescription>
                  )}
                </div>
              </div>
            </Field>
          );
        }}
      </form.Field>
      <form.Field name="displayName">
        {field => (
          <Field>
            <FieldLabel htmlFor="profile-name">Display name</FieldLabel>
            <Input
              id="profile-name"
              name="name"
              autoComplete="name"
              required
              minLength={1}
              maxLength={100}
              pattern={".*\\S.*"}
              disabled={busy}
              value={field.state.value}
              onBlur={field.handleBlur}
              onChange={event => {
                field.handleChange(event.target.value);
                update.reset();
              }}
            />
          </Field>
        )}
      </form.Field>
      <p className="text-sm break-all text-muted-foreground">{profile.email}</p>
      {error && (
        <Alert id="profile-error" variant="destructive">
          <AlertDescription>{error}</AlertDescription>
        </Alert>
      )}
      {update.isSuccess && (
        <p
          id="profile-saved"
          role="status"
          className="text-sm text-muted-foreground"
        >
          Profile saved.
        </p>
      )}
      <Button
        id="profile-save"
        type="submit"
        isLoading={busy}
        disabled={Boolean(fileError)}
        className="w-full"
      >
        Save profile
      </Button>
    </form>
  );
}
