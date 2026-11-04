import type { AuthField } from "./auth.ts";

export type AuthValues = Record<AuthField, string>;
export type AuthFieldErrors = Partial<Record<AuthField, string>>;

export type AuthFieldSpec = { name: AuthField; label: string };

function validateField(
  { name, label }: AuthFieldSpec,
  values: AuthValues,
  settingPassword: boolean
) {
  const value = values[name];
  if (name === "display_name" ? !value.trim() : !value)
    return `${label} is required.`;
  if (name === "display_name" && value.trim().length > 100)
    return "Use a name between 1 and 100 characters.";
  if (name === "email" && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value))
    return "Enter a valid email address.";
  if (name === "password" && settingPassword && value.length < 8)
    return "Use at least 8 characters.";
  if (name === "password_confirmation" && value !== values.password)
    return "Passwords must match.";
  return undefined;
}

/**
 * Before the first submit attempt, only a filled confirmation field can show an
 * error. A filled mismatch is useful feedback; an empty field is not an error yet.
 */
export function validateAuthFields(
  fields: AuthFieldSpec[],
  values: AuthValues,
  {
    settingPassword,
    attempted,
  }: { settingPassword: boolean; attempted: boolean }
): AuthFieldErrors {
  const errors: AuthFieldErrors = {};
  for (const spec of fields) {
    if (
      !attempted &&
      (spec.name !== "password_confirmation" || !values.password_confirmation)
    )
      continue;
    const error = validateField(spec, values, settingPassword);
    if (error) errors[spec.name] = error;
  }
  return errors;
}

/**
 * Decides whether a form event runs validation:
 * - Submit always validates.
 * - Change and blur validate only after a submit attempt, or after the person
 *   has left the confirmation field once.
 */
export function shouldValidate({
  event,
  attempted,
  confirmationLeft,
}: {
  event: "blur" | "change" | "submit" | "mount" | "server";
  attempted: boolean;
  confirmationLeft: boolean;
}) {
  if (event === "submit") return true;
  if (event === "change" || event === "blur")
    return attempted || confirmationLeft;
  return false;
}
