import { useState } from "react";
import { Link, useNavigate, useRouter } from "@tanstack/react-router";
import { useQueryClient } from "@tanstack/react-query";
import { useForm } from "@tanstack/react-form";

import type { AuthField } from "../lib/auth";

import { Input } from "./ui/input";
import { Field, FieldLabel, FieldDescription, FieldError } from "./ui/field";
import { Button, buttonVariants } from "./ui/button";
import { Alert, AlertDescription } from "./ui/alert";
import { authRedirect, consumeAuthRedirect } from "../lib/redirect";
import { AuthError, sessionRequest } from "../lib/auth";

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
  | { mode: "register" | "sign-in"; redirect?: string }
  | { mode: "reset-request"; redirect?: string }
  | { mode: "reset-password"; token: string; redirect?: string };

function validateField(
  name: string,
  label: string,
  value: string,
  settingPassword: boolean,
  form: { getFieldValue: (name: "password") => string }
) {
  if (name === "display_name" ? !value.trim() : !value)
    return `${label} is required.`;
  if (name === "display_name" && value.trim().length > 100)
    return "Use a name between 1 and 100 characters.";
  if (name === "email" && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value))
    return "Enter a valid email address.";
  if (name === "password" && settingPassword && value.length < 8)
    return "Use at least 8 characters.";
  if (
    name === "password_confirmation" &&
    value !== form.getFieldValue("password")
  )
    return "Passwords must match.";
  return undefined;
}

export function AuthForm(props: AuthFormProps) {
  const { mode } = props;
  const destination = authRedirect(props.redirect);
  const queryClient = useQueryClient();
  const registering = mode === "register";
  const settingPassword = registering || mode === "reset-password";
  const copy = modes[mode];
  const router = useRouter();
  const navigate = useNavigate();
  const [complete, setComplete] = useState(false);
  const [error, setError] = useState("");
  const [serverErrors, setServerErrors] = useState<
    Partial<Record<AuthField, string>>
  >({});
  const form = useForm({
    defaultValues: {
      display_name: "",
      email: "",
      password: "",
      password_confirmation: "",
    },
    onSubmit: async ({ value }) => {
      setError("");
      setServerErrors({});
      try {
        const user: Record<string, string> =
          props.mode === "reset-password"
            ? {
                password: value.password,
                password_confirmation: value.password_confirmation,
                reset_token: props.token,
              }
            : mode === "reset-request"
              ? { email: value.email }
              : registering
                ? value
                : { email: value.email, password: value.password };
        const session = await sessionRequest(copy.endpoint, {
          method: "POST",
          queryClient,
          user,
        });
        // Registration signs nobody in: the person must confirm the email first.
        if (
          mode === "reset-request" ||
          mode === "reset-password" ||
          (registering && !session.user)
        ) {
          if (mode === "reset-password") await router.invalidate();
          setComplete(true);
        } else {
          await router.invalidate();
          await navigate({ href: consumeAuthRedirect(destination) });
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
    const done = {
      register: {
        id: "confirmation-sent",
        title: "Check your inbox",
        text: "We sent you a link. Confirm your email address to continue where you left off.",
      },
      "reset-request": {
        id: "reset-request-sent",
        title: "Check your inbox",
        text: "If an account exists for this email address, you will receive a password reset link.",
      },
      "reset-password": {
        id: "password-reset-complete",
        title: "Password reset",
        text: "Sign in with your new password. Your previous sessions have been signed out.",
      },
    }[mode as "register" | "reset-request" | "reset-password"];

    return (
      <div id={done.id} role="status">
        <h1 className="text-3xl font-semibold tracking-tight">{done.title}</h1>
        <p className="mt-4 text-sm leading-7 text-muted-foreground">
          {done.text}
        </p>
        <Link
          to="/sign-in"
          search={{ redirect: destination }}
          className={buttonVariants({ variant: "link", className: "mt-6" })}
        >
          Back to sign in
        </Link>
      </div>
    );
  }

  const fields = [
    ...(registering
      ? [
          {
            name: "display_name",
            label: "Display name",
            type: "text",
            autoComplete: "name",
          },
        ]
      : []),
    ...(mode !== "reset-password"
      ? [
          {
            name: "email",
            label: "Email address",
            type: "email",
            autoComplete: "email",
          },
        ]
      : []),
    ...(mode !== "reset-request"
      ? [
          {
            name: "password",
            label: "Password",
            type: "password",
            autoComplete: settingPassword ? "new-password" : "current-password",
          },
        ]
      : []),
    ...(settingPassword
      ? [
          {
            name: "password_confirmation",
            label: "Confirm password",
            type: "password",
            autoComplete: "new-password",
          },
        ]
      : []),
  ];

  return (
    <>
      <h1 className="text-3xl font-semibold tracking-tight">{copy.title}</h1>
      <p className="mt-3 text-sm leading-6 text-muted-foreground">
        {copy.description}
      </p>
      <form
        id={`${mode}-form`}
        className="mt-8 space-y-5"
        onSubmit={event => {
          event.preventDefault();
          void form.handleSubmit();
        }}
      >
        {fields.map(({ name, label, type, autoComplete }) => (
          <form.Field
            key={name}
            name={name as AuthField}
            validators={
              name === "password_confirmation"
                ? {
                    // onBlur errors are kept apart from onChange errors and would go stale
                    // when the password changes, leaving the button disabled.
                    onChange: ({ value, fieldApi }) =>
                      validateField(
                        name,
                        label,
                        value,
                        settingPassword,
                        fieldApi.form
                      ),
                    onChangeListenTo: ["password"],
                  }
                : {
                    onBlur: ({ value, fieldApi }) =>
                      validateField(
                        name,
                        label,
                        value,
                        settingPassword,
                        fieldApi.form
                      ),
                  }
            }
          >
            {field => {
              const serverError = serverErrors[name as AuthField];
              const invalid =
                !!serverError ||
                ((name === "password_confirmation"
                  ? field.state.meta.isBlurred
                  : field.state.meta.isTouched) &&
                  !field.state.meta.isValid);
              return (
                <Field data-invalid={invalid}>
                  <FieldLabel htmlFor={name}>{label}</FieldLabel>
                  <Input
                    id={name}
                    name={name}
                    type={type}
                    autoComplete={autoComplete}
                    autoCapitalize={name === "display_name" ? "words" : "none"}
                    spellCheck={false}
                    required
                    maxLength={name === "display_name" ? 100 : undefined}
                    pattern={name === "display_name" ? ".*\\S.*" : undefined}
                    minLength={
                      name === "password" && settingPassword ? 8 : undefined
                    }
                    value={field.state.value}
                    onChange={event => {
                      field.handleChange(event.target.value);
                      setServerErrors(errors => ({
                        ...errors,
                        [name]: undefined,
                      }));
                    }}
                    onBlur={field.handleBlur}
                    aria-invalid={invalid}
                    aria-describedby={invalid ? `${name}-error` : undefined}
                  />
                  {invalid && (
                    <FieldError id={`${name}-error`}>
                      {serverError ?? field.state.meta.errors.join(" ")}
                    </FieldError>
                  )}
                </Field>
              );
            }}
          </form.Field>
        ))}
        {settingPassword && (
          <FieldDescription>
            Use at least 8 characters for your password.
          </FieldDescription>
        )}
        {error && (
          <Alert id="auth-error" variant="destructive">
            <AlertDescription>{error}</AlertDescription>
          </Alert>
        )}
        <form.Subscribe
          selector={state => [state.canSubmit, state.isSubmitting]}
        >
          {([canSubmit, submitting]) => (
            <Button
              id="auth-submit"
              type="submit"
              isLoading={submitting}
              disabled={!canSubmit}
              className="w-full"
            >
              {copy.button}
            </Button>
          )}
        </form.Subscribe>
      </form>
      {(registering || mode === "sign-in") && (
        <p className="mt-6 text-center text-sm text-muted-foreground">
          {registering ? "Already have an account? " : "New here? "}
          <Link
            to={registering ? "/sign-in" : "/register"}
            search={{ redirect: destination }}
            className={buttonVariants({
              variant: "link",
              className: "h-auto p-0",
            })}
          >
            {registering ? "Sign in" : "Create an account"}
          </Link>
        </p>
      )}
      {mode === "sign-in" && (
        <p className="mt-4 text-center text-sm">
          <Link
            to="/reset"
            search={{ redirect: destination }}
            className={buttonVariants({ variant: "link" })}
          >
            Forgot password?
          </Link>
        </p>
      )}
      {mode === "reset-request" && (
        <p className="mt-6 text-center text-sm">
          <Link
            to="/sign-in"
            search={{ redirect: destination }}
            className={buttonVariants({ variant: "link" })}
          >
            Back to sign in
          </Link>
        </p>
      )}
      {mode === "reset-password" && (
        <p className="mt-6 text-center text-sm">
          <Link
            to="/reset"
            search={{ redirect: destination }}
            className={buttonVariants({ variant: "link" })}
          >
            Request a new reset link
          </Link>
        </p>
      )}
    </>
  );
}
