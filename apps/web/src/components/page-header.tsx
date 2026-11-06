import { Fragment, type ReactNode } from "react";
import { ChevronLeftIcon } from "lucide-react";
import { cn } from "cn";
import { Link } from "@tanstack/react-router";

import {
  Breadcrumb,
  BreadcrumbItem,
  BreadcrumbLink,
  BreadcrumbList,
  BreadcrumbPage,
  BreadcrumbSeparator,
} from "./ui/breadcrumb";

// `campaignId` links the crumb to that campaign's page. `list` links it to that campaign's list.
type Crumb = {
  label: string;
  to?: "/campaigns" | "/skills";
  campaignId?: string;
  list?: {
    campaignId: string;
    kind: "notes" | "sessions" | "characters" | "entries";
  };
};

const LIST_PATHS = {
  notes: "/campaigns/$campaignId/notes",
  sessions: "/campaigns/$campaignId/sessions",
  characters: "/campaigns/$campaignId/characters",
  entries: "/campaigns/$campaignId/entries",
} as const;

export function PageHeader({
  crumbs,
  title,
  description,
  actions,
  leading,
}: {
  crumbs: Crumb[];
  title: string;
  description?: ReactNode;
  actions?: ReactNode;
  leading?: ReactNode;
}) {
  // A small screen shows only the parent crumb, as a back link. The title names the page.
  const parentIndex = crumbs.length - 2;
  return (
    <header className="space-y-3 sm:space-y-4">
      {crumbs.length > 1 && (
        <Breadcrumb>
          <BreadcrumbList>
            {crumbs.map((crumb, index) => (
              <Fragment key={crumb.label}>
                {index > 0 && <BreadcrumbSeparator className="max-sm:hidden" />}
                <BreadcrumbItem
                  className={cn(
                    "min-w-0",
                    index !== parentIndex && "max-sm:hidden"
                  )}
                >
                  {index === parentIndex && (
                    <ChevronLeftIcon
                      aria-hidden="true"
                      className="-mr-1 size-4 shrink-0 sm:hidden"
                    />
                  )}
                  {crumb.to ? (
                    <BreadcrumbLink
                      className="truncate max-sm:py-1.5"
                      render={<Link to={crumb.to} />}
                    >
                      {crumb.label}
                    </BreadcrumbLink>
                  ) : crumb.list ? (
                    <BreadcrumbLink
                      className="truncate max-sm:py-1.5"
                      render={
                        <Link
                          to={LIST_PATHS[crumb.list.kind]}
                          params={{ campaignId: crumb.list.campaignId }}
                        />
                      }
                    >
                      {crumb.label}
                    </BreadcrumbLink>
                  ) : crumb.campaignId ? (
                    <BreadcrumbLink
                      className="truncate max-sm:py-1.5"
                      render={
                        <Link
                          to="/campaigns/$campaignId"
                          params={{ campaignId: crumb.campaignId }}
                        />
                      }
                    >
                      {crumb.label}
                    </BreadcrumbLink>
                  ) : (
                    <BreadcrumbPage>{crumb.label}</BreadcrumbPage>
                  )}
                </BreadcrumbItem>
              </Fragment>
            ))}
          </BreadcrumbList>
        </Breadcrumb>
      )}
      <div className="flex flex-wrap items-center justify-between gap-3 sm:gap-4">
        <div className="flex min-w-0 items-center gap-3 sm:gap-4">
          {leading}
          <div className="min-w-0">
            <h1
              id="page-title"
              className="font-heading text-2xl/tight font-semibold tracking-tight wrap-break-word sm:truncate sm:text-4xl"
            >
              {title}
            </h1>
            {description && (
              <p className="mt-1 text-sm text-muted-foreground">
                {description}
              </p>
            )}
          </div>
        </div>
        {actions}
      </div>
    </header>
  );
}
