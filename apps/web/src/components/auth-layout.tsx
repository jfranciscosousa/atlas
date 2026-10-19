import type { ReactNode } from "react";

import { CompassIcon } from "lucide-react";
import { Link } from "@tanstack/react-router";

export function AuthLayout({ children }: { children: ReactNode }) {
  return (
    <div className="grid min-h-screen lg:grid-cols-[minmax(0,1.1fr)_minmax(0,1fr)]">
      <aside className="relative hidden overflow-hidden bg-sidebar text-sidebar-foreground lg:flex lg:flex-col lg:justify-between lg:p-12">
        <div
          aria-hidden="true"
          className="absolute inset-0 opacity-60"
          style={{
            backgroundImage:
              "radial-gradient(circle at 20% 15%, oklch(0.42 0.14 285 / 0.55), transparent 45%), radial-gradient(circle at 85% 90%, oklch(0.78 0.14 75 / 0.22), transparent 40%), repeating-linear-gradient(135deg, oklch(1 0 0 / 0.035) 0 1px, transparent 1px 28px)",
          }}
        />
        <Link
          to="/"
          className="relative flex items-center gap-2.5 font-heading text-xl font-semibold tracking-wide text-sidebar-accent-foreground"
        >
          <span className="flex size-9 items-center justify-center rounded-lg bg-sidebar-primary text-sidebar-primary-foreground">
            <CompassIcon aria-hidden="true" className="size-5" />
          </span>
          Atlas
        </Link>
        <div className="relative max-w-md space-y-4">
          <p className="font-heading text-4xl leading-tight font-medium tracking-tight text-sidebar-accent-foreground">
            Every world deserves a map worth keeping.
          </p>
          <p className="text-sm leading-6 text-sidebar-foreground/70">
            Keep your campaign’s lore, sessions, and secrets in one place. Share
            what the table should know, and keep the rest behind the screen.
          </p>
        </div>
      </aside>
      <main className="flex flex-col justify-center px-6 py-10 sm:px-12">
        <Link
          to="/"
          className="mb-10 flex items-center gap-2.5 font-heading text-lg font-semibold tracking-wide lg:hidden"
        >
          <span className="flex size-8 items-center justify-center rounded-lg bg-sidebar text-sidebar-primary">
            <CompassIcon aria-hidden="true" className="size-4" />
          </span>
          Atlas
        </Link>
        <div className="mx-auto w-full max-w-sm">{children}</div>
      </main>
    </div>
  );
}
