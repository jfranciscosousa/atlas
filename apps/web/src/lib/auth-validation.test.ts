import { test } from "node:test";
import assert from "node:assert/strict";

import {
  shouldValidate,
  validateAuthFields,
  type AuthFieldSpec,
  type AuthValues,
} from "./auth-validation.ts";

const registerFields: AuthFieldSpec[] = [
  { name: "display_name", label: "Display name" },
  { name: "email", label: "Email address" },
  { name: "password", label: "Password" },
  { name: "password_confirmation", label: "Confirm password" },
];

const empty: AuthValues = {
  display_name: "",
  email: "",
  password: "",
  password_confirmation: "",
};

test("an untouched form shows no errors before the first submit", () => {
  assert.deepEqual(
    validateAuthFields(registerFields, empty, {
      settingPassword: true,
      attempted: false,
    }),
    {}
  );
});

test("a filled confirmation that does not match shows an error before submit", () => {
  assert.deepEqual(
    validateAuthFields(
      registerFields,
      { ...empty, password: "longenough", password_confirmation: "different" },
      { settingPassword: true, attempted: false }
    ),
    { password_confirmation: "Passwords must match." }
  );
});

test("the first submit reports every invalid field", () => {
  assert.deepEqual(
    validateAuthFields(registerFields, empty, {
      settingPassword: true,
      attempted: true,
    }),
    {
      display_name: "Display name is required.",
      email: "Email address is required.",
      password: "Password is required.",
      password_confirmation: "Confirm password is required.",
    }
  );
});

test("each rule has its own message", () => {
  const errors = validateAuthFields(
    registerFields,
    {
      display_name: "   ",
      email: "not-an-email",
      password: "short",
      password_confirmation: "other",
    },
    { settingPassword: true, attempted: true }
  );
  assert.deepEqual(errors, {
    display_name: "Display name is required.",
    email: "Enter a valid email address.",
    password: "Use at least 8 characters.",
    password_confirmation: "Passwords must match.",
  });
});

test("sign-in does not enforce the password length", () => {
  const signIn = registerFields.slice(1, 3);
  assert.deepEqual(
    validateAuthFields(
      signIn,
      { ...empty, email: "a@b.co", password: "x" },
      { settingPassword: false, attempted: true }
    ),
    {}
  );
});

test("fixing the password clears the confirmation mismatch", () => {
  const values = {
    ...empty,
    display_name: "Ada",
    email: "ada@example.com",
    password: "longenough",
    password_confirmation: "longenough",
  };
  assert.deepEqual(
    validateAuthFields(registerFields, values, {
      settingPassword: true,
      attempted: true,
    }),
    {}
  );
});

test("fields missing from the mode are not validated", () => {
  const reset = registerFields.slice(2);
  assert.deepEqual(
    validateAuthFields(reset, empty, {
      settingPassword: true,
      attempted: true,
    }),
    {
      password: "Password is required.",
      password_confirmation: "Confirm password is required.",
    }
  );
});

test("submit always validates", () => {
  assert.equal(
    shouldValidate({
      event: "submit",
      attempted: false,
      confirmationLeft: false,
    }),
    true
  );
});

test("blur and change do not validate before the first submit", () => {
  for (const event of ["blur", "change"] as const)
    assert.equal(
      shouldValidate({ event, attempted: false, confirmationLeft: false }),
      false
    );
});

test("blur and change validate after a submit attempt", () => {
  for (const event of ["blur", "change"] as const)
    assert.equal(
      shouldValidate({ event, attempted: true, confirmationLeft: false }),
      true
    );
});

test("blur and change validate once the confirmation field was left", () => {
  for (const event of ["blur", "change"] as const)
    assert.equal(
      shouldValidate({ event, attempted: false, confirmationLeft: true }),
      true
    );
});

test("mount and server events never validate", () => {
  for (const event of ["mount", "server"] as const)
    assert.equal(
      shouldValidate({ event, attempted: true, confirmationLeft: true }),
      false
    );
});
