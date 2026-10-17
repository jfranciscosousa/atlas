import { useState } from "react";
import { useForm } from "@tanstack/react-form";

import { Input } from "./ui/input";
import { Field, FieldLabel } from "./ui/field";
import { Button } from "./ui/button";
import { Alert, AlertDescription } from "./ui/alert";
import { readAvatar } from "../lib/avatar";
import { useProfile, useProfileUpdate } from "../hooks/use-profile";

export function ProfileForm({ userId }: { userId: string }) {
  const { data: profile } = useProfile(userId);
  const update = useProfileUpdate(userId);
  const [fileError, setFileError] = useState("");
  const [reading, setReading] = useState(false);
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
      className="mt-7 space-y-6"
      aria-busy={busy}
      onSubmit={event => {
        event.preventDefault();
        if (!busy && !fileError) void form.handleSubmit();
      }}
    >
      <form.Field name="avatar">
        {field => (
          <Field>
            <FieldLabel htmlFor="profile-avatar">Profile photo</FieldLabel>
            <div className="flex items-center gap-4">
              {field.state.value ? (
                <img
                  id="profile-avatar-preview"
                  src={field.state.value}
                  alt="Your profile photo"
                  className="size-20 rounded-full border border-border object-cover"
                />
              ) : (
                <div
                  className="flex size-20 shrink-0 items-center justify-center rounded-full bg-muted text-2xl font-semibold text-muted-foreground"
                  aria-label="No profile photo"
                >
                  {(profile.displayName || profile.email)
                    .slice(0, 1)
                    .toUpperCase()}
                </div>
              )}
              <div className="min-w-0 flex-1">
                <Input
                  id="profile-avatar"
                  type="file"
                  accept="image/png,image/jpeg,image/webp"
                  aria-describedby="profile-avatar-help"
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
                <p
                  id="profile-avatar-help"
                  className="mt-2 text-xs text-muted-foreground"
                >
                  PNG, JPEG, or WebP. Up to 512 KB.
                </p>
              </div>
            </div>
            {(field.state.value || fileError) && (
              <Button
                id="profile-avatar-remove"
                type="button"
                variant="ghost"
                size="sm"
                className="self-start"
                disabled={busy}
                onClick={() => {
                  field.handleChange(null);
                  setFileError("");
                  update.reset();
                }}
              >
                Remove photo
              </Button>
            )}
          </Field>
        )}
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
        disabled={busy || Boolean(fileError)}
        className="w-full"
      >
        {reading
          ? "Reading photo…"
          : update.isPending
            ? "Saving…"
            : "Save profile"}
      </Button>
    </form>
  );
}
