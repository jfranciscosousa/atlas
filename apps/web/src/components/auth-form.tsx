import { useState } from "react";
import { useForm } from "@tanstack/react-form";
import { useQueryClient } from "@tanstack/react-query";
import { Link, useNavigate, useRouter } from "@tanstack/react-router";
import { AuthError, sessionRequest } from "../lib/auth";
import type { AuthField } from "../lib/auth";

const modes = {
  register: {
    title: "Create your account",
    description: "Enter your details to get started.",
    button: "Create account",
    endpoint: "/auth/user/password/register",
  },
  "sign-in": {
    title: "Welcome back",
    description: "Sign in to your Atlas account.",
    button: "Sign in",
    endpoint: "/auth/user/password/sign_in",
  },
  "reset-request": {
    title: "Reset your password",
    description: "Enter your email address to request a reset link.",
    button: "Send reset link",
    endpoint: "/auth/user/password/reset_request",
  },
  "reset-password": {
    title: "Choose a new password",
    description: "Enter your new password below.",
    button: "Reset password",
    endpoint: "/auth/user/password/reset",
  },
};

type AuthFormProps =
  | { mode: "register" | "sign-in" | "reset-request" }
  | { mode: "reset-password"; token: string };

export function AuthForm(props: AuthFormProps) {
  const { mode } = props;
  const queryClient = useQueryClient();
  const registering = mode === "register";
  const settingPassword = registering || mode === "reset-password";
  const copy = modes[mode];
  const router = useRouter();
  const navigate = useNavigate();
  const [complete, setComplete] = useState(false);
  const [error, setError] = useState("");
  const [serverErrors, setServerErrors] = useState<Partial<Record<AuthField, string>>>({});
  const form = useForm({
    defaultValues: { email: "", password: "", password_confirmation: "" },
    onSubmit: async ({ value }) => {
      setError("");
      setServerErrors({});
      try {
        const user: Record<string, string> = props.mode === "reset-password"
          ? { password: value.password, password_confirmation: value.password_confirmation, reset_token: props.token }
          : mode === "reset-request"
            ? { email: value.email }
            : registering ? value : { email: value.email, password: value.password };
        await sessionRequest(copy.endpoint, {
          method: "POST",
          queryClient,
          user,
        });
        if (mode === "reset-request" || mode === "reset-password") {
          if (mode === "reset-password") await router.invalidate();
          setComplete(true);
        } else {
          await router.invalidate();
          await navigate({ to: "/dashboard" });
        }
      } catch (reason) {
        if (reason instanceof AuthError) {
          setServerErrors(reason.fields);
          const firstField = Object.keys(reason.fields)[0];
          if (firstField) {
            document.getElementById(firstField)?.focus();
          } else {
            setError(reason.message);
          }
        } else {
          setError("Could not connect. Please try again.");
        }
      }
    },
  });

  if (complete) {
    return (
      <div id={mode === "reset-request" ? "reset-request-sent" : "password-reset-complete"} role="status">
        <h1 className="text-3xl font-semibold tracking-tight">{mode === "reset-request" ? "Check your inbox" : "Password reset"}</h1>
        <p className="mt-4 text-sm leading-7 text-emerald-950/65">
          {mode === "reset-request"
            ? "If an account exists for this email address, you will receive a password reset link."
            : "Sign in with your new password. Your previous sessions have been signed out."}
        </p>
        <Link to="/sign-in" className="mt-6 inline-block font-semibold underline">Back to sign in</Link>
      </div>
    );
  }

  const fields = [
    ...(mode !== "reset-password" ? [{ name: "email", label: "Email address", type: "email", autoComplete: "email" }] : []),
    ...(mode !== "reset-request" ? [{ name: "password", label: "Password", type: "password", autoComplete: settingPassword ? "new-password" : "current-password" }] : []),
    ...(settingPassword ? [{ name: "password_confirmation", label: "Confirm password", type: "password", autoComplete: "new-password" }] : []),
  ];

  return (
    <>
      <h1 className="text-3xl font-semibold tracking-tight">{copy.title}</h1>
      <p className="mt-3 text-sm leading-6 text-emerald-950/65">{copy.description}</p>
      <form id={`${mode}-form`} className="mt-8 space-y-5" onSubmit={(event) => {
        event.preventDefault();
        void form.handleSubmit();
      }}>
        {fields.map(({ name, label, type, autoComplete }) => (
          <form.Field
            key={name}
            name={name as AuthField}
            validators={{
              onBlur: ({ value, fieldApi }) => {
                if (!value) return `${label} is required.`;
                if (name === "email" && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value)) return "Enter a valid email address.";
                if (name === "password" && settingPassword && value.length < 8) return "Use at least 8 characters.";
                if (name === "password_confirmation" && value !== fieldApi.form.getFieldValue("password")) return "Passwords must match.";
                return undefined;
              },
            }}
          >
            {(field) => {
              const serverError = serverErrors[name as AuthField];
              const invalid = !!serverError || (field.state.meta.isTouched && !field.state.meta.isValid);
              return (
                <div>
                  <label htmlFor={name} className="mb-2 block text-sm font-medium">{label}</label>
                  <input
                    id={name}
                    name={name}
                    type={type}
                    autoComplete={autoComplete}
                    autoCapitalize="none"
                    spellCheck={false}
                    required
                    minLength={name === "password" && settingPassword ? 8 : undefined}
                    value={field.state.value}
                    onChange={(event) => {
                      field.handleChange(event.target.value);
                      setServerErrors((errors) => ({ ...errors, [name]: undefined }));
                    }}
                    onBlur={field.handleBlur}
                    aria-invalid={invalid}
                    aria-describedby={invalid ? `${name}-error` : undefined}
                    className="w-full rounded-xl border border-emerald-950/20 bg-white px-4 py-3 text-base outline-none transition focus:border-emerald-700 focus:ring-3 focus:ring-emerald-100 aria-invalid:border-red-600"
                  />
                  {invalid && <p id={`${name}-error`} className="mt-2 text-sm text-red-700">{serverError ?? field.state.meta.errors.join(" ")}</p>}
                </div>
              );
            }}
          </form.Field>
        ))}
        {settingPassword && <p className="text-xs leading-5 text-emerald-950/70">Use at least 8 characters for your password.</p>}
        {error && <p id="auth-error" role="alert" className="rounded-xl bg-red-50 p-4 text-sm text-red-800">{error}</p>}
        <form.Subscribe selector={(state) => [state.canSubmit, state.isSubmitting]}>
          {([canSubmit, submitting]) => (
            <button id="auth-submit" type="submit" disabled={!canSubmit || submitting} className="primary-button w-full">
              {submitting ? "Please wait…" : copy.button}
            </button>
          )}
        </form.Subscribe>
      </form>
      {(registering || mode === "sign-in") && <p className="mt-6 text-center text-sm text-emerald-950/65">
        {registering ? "Already have an account? " : "New here? "}
        <Link to={registering ? "/sign-in" : "/register"} className="font-semibold text-emerald-900 underline underline-offset-4">
          {registering ? "Sign in" : "Create an account"}
        </Link>
      </p>}
      {mode === "sign-in" && <p className="mt-4 text-center text-sm"><Link to="/reset" className="text-emerald-950/65 underline underline-offset-4">Forgot password?</Link></p>}
      {mode === "reset-request" && <p className="mt-6 text-center text-sm"><Link to="/sign-in" className="font-semibold underline">Back to sign in</Link></p>}
      {mode === "reset-password" && <p className="mt-6 text-center text-sm"><Link to="/reset" className="font-semibold underline">Request a new reset link</Link></p>}
    </>
  );
}
