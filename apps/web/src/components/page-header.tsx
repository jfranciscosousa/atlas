import { Fragment, type ReactNode } from "react";
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
  to?: "/campaigns";
  campaignId?: string;
  list?: { campaignId: string; kind: "notes" | "sessions" };
};

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
  return (
    <header className="space-y-4">
      {crumbs.length > 1 && (
        <Breadcrumb>
          <BreadcrumbList>
            {crumbs.map((crumb, index) => (
              <Fragment key={crumb.label}>
                {index > 0 && <BreadcrumbSeparator />}
                <BreadcrumbItem>
                  {crumb.to ? (
                    <BreadcrumbLink render={<Link to={crumb.to} />}>
                      {crumb.label}
                    </BreadcrumbLink>
                  ) : crumb.list ? (
                    <BreadcrumbLink
                      render={
                        <Link
                          to={
                            crumb.list.kind === "notes"
                              ? "/campaigns/$campaignId/notes"
                              : "/campaigns/$campaignId/sessions"
                          }
                          params={{ campaignId: crumb.list.campaignId }}
                        />
                      }
                    >
                      {crumb.label}
                    </BreadcrumbLink>
                  ) : crumb.campaignId ? (
                    <BreadcrumbLink
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
      <div className="flex flex-wrap items-center justify-between gap-4">
        <div className="flex min-w-0 items-center gap-4">
          {leading}
          <div className="min-w-0">
            <h1
              id="page-title"
              className="truncate font-heading text-3xl font-semibold tracking-tight sm:text-4xl"
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
