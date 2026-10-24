import {
  cloneElement,
  useEffect,
  useRef,
  useState,
  type ReactElement,
  type ReactNode,
} from "react";
import {
  BookOpenTextIcon,
  CalendarDaysIcon,
  ChevronRightIcon,
  EyeIcon,
  ScrollTextIcon,
  UsersIcon,
} from "lucide-react";
import { cn } from "cn";
import { Link } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";

import {
  SidebarMenuAction,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarMenuSub,
  SidebarMenuSubButton,
  SidebarMenuSubItem,
} from "./ui/sidebar";
import { CampaignAvatar } from "./campaign-avatar";
import { sessionsQueryOptions } from "../hooks/use-sessions";
import { notesQueryOptions } from "../hooks/use-notes";
import { charactersQueryOptions } from "../hooks/use-characters";

type Campaign = { id: string; name: string; isGm: boolean | null };

/** The lists a campaign has. The count is how many the signed-in person may read. */
function useResourceCounts(campaignId: string, enabled: boolean) {
  const sessions = useQuery({ ...sessionsQueryOptions(campaignId), enabled });
  const characters = useQuery({
    ...charactersQueryOptions(campaignId),
    enabled,
  });
  const notes = useQuery({
    ...notesQueryOptions(campaignId, false),
    enabled,
  });
  return {
    sessions: sessions.data?.length,
    characters: characters.data?.length,
    notes: notes.data?.length,
    refetch: () => {
      // Do not cancel a fetch that already runs: a page may have started it.
      const options = { cancelRefetch: false };
      void sessions.refetch(options);
      void characters.refetch(options);
      void notes.refetch(options);
    },
  };
}

export function CampaignNav({
  campaign,
  pathname,
  onNavigate,
}: {
  campaign: Campaign;
  pathname: string;
  onNavigate: () => void;
}) {
  const base = `/campaigns/${campaign.id}`;
  const isCurrent = pathname === base || pathname.startsWith(`${base}/`);
  // Until the person toggles it, a campaign is open exactly while they are inside it.
  const [chosen, setChosen] = useState<boolean>();
  const open = chosen ?? isCurrent;
  const counts = useResourceCounts(campaign.id, open);

  // Lists change without a refetch of their own; follow every move inside the campaign.
  const { refetch } = counts;
  const lastPath = useRef(pathname);
  useEffect(() => {
    if (lastPath.current === pathname) return;
    lastPath.current = pathname;
    if (open) refetch();
  }, [pathname, open, refetch]);

  const isActive = (segment?: string) =>
    segment
      ? pathname === `${base}/${segment}` ||
        pathname.startsWith(`${base}/${segment}/`)
      : pathname === base;

  return (
    <SidebarMenuItem>
      <SidebarMenuButton
        isActive={pathname === base}
        className={cn(
          isCurrent && "font-medium text-sidebar-accent-foreground"
        )}
        render={
          <Link
            to="/campaigns/$campaignId"
            params={{ campaignId: campaign.id }}
            onClick={onNavigate}
          />
        }
      >
        <CampaignAvatar
          id={campaign.id}
          name={campaign.name}
          className="size-5 rounded-md text-[0.65rem]"
        />
        <span className="truncate">{campaign.name}</span>
        {campaign.isGm && (
          <span
            title="You are the GM"
            className="ml-auto shrink-0 rounded-sm bg-sidebar-primary/15 px-1 py-px text-[0.6rem] font-semibold tracking-wider text-sidebar-primary"
          >
            GM
          </span>
        )}
      </SidebarMenuButton>
      <SidebarMenuAction
        aria-expanded={open}
        aria-label={`${open ? "Collapse" : "Expand"} ${campaign.name}`}
        onClick={() => setChosen(!open)}
      >
        <ChevronRightIcon
          aria-hidden="true"
          className={cn(
            "transition-transform duration-200 motion-reduce:transition-none",
            open && "rotate-90"
          )}
        />
      </SidebarMenuAction>
      {/* A grid row that animates from 0fr to 1fr opens the list without a measured height. */}
      <div
        className={cn(
          "grid transition-[grid-template-rows,opacity] duration-200 ease-out motion-reduce:transition-none",
          open ? "grid-rows-[1fr] opacity-100" : "grid-rows-[0fr] opacity-0"
        )}
        inert={!open}
      >
        <div className="overflow-hidden">
          <SidebarMenuSub
            className={cn(
              "my-1",
              isCurrent ? "border-sidebar-primary/40" : "border-sidebar-border"
            )}
          >
            <ResourceLink
              active={isActive()}
              icon={<BookOpenTextIcon aria-hidden="true" />}
              label="Overview"
              onClick={onNavigate}
              link={
                <Link
                  to="/campaigns/$campaignId"
                  params={{ campaignId: campaign.id }}
                />
              }
            />
            <ResourceLink
              active={isActive("sessions")}
              icon={<CalendarDaysIcon aria-hidden="true" />}
              label="Sessions"
              count={counts.sessions}
              onClick={onNavigate}
              link={
                <Link
                  to="/campaigns/$campaignId/sessions"
                  params={{ campaignId: campaign.id }}
                />
              }
            />
            <ResourceLink
              active={isActive("characters")}
              icon={<UsersIcon aria-hidden="true" />}
              label="Characters"
              count={counts.characters}
              onClick={onNavigate}
              link={
                <Link
                  to="/campaigns/$campaignId/characters"
                  params={{ campaignId: campaign.id }}
                />
              }
            />
            <ResourceLink
              active={isActive("notes")}
              icon={<ScrollTextIcon aria-hidden="true" />}
              label="Notes"
              count={counts.notes}
              onClick={onNavigate}
              link={
                <Link
                  to="/campaigns/$campaignId/notes"
                  params={{ campaignId: campaign.id }}
                />
              }
            />
            {campaign.isGm && (
              <ResourceLink
                active={isActive("preview")}
                icon={<EyeIcon aria-hidden="true" />}
                label="Preview as player"
                onClick={onNavigate}
                link={
                  <Link
                    to="/campaigns/$campaignId/preview"
                    params={{ campaignId: campaign.id }}
                  />
                }
              />
            )}
          </SidebarMenuSub>
        </div>
      </div>
    </SidebarMenuItem>
  );
}

function ResourceLink({
  active,
  icon,
  label,
  count,
  link,
  onClick,
}: {
  active: boolean;
  icon: ReactNode;
  label: string;
  count?: number;
  link: ReactElement<{ onClick?: () => void }>;
  onClick: () => void;
}) {
  return (
    <SidebarMenuSubItem>
      <SidebarMenuSubButton
        isActive={active}
        className="text-sidebar-foreground/80 data-active:font-medium [&>svg]:text-sidebar-foreground/60 data-active:[&>svg]:text-sidebar-primary"
        render={cloneElement(link, { onClick })}
      >
        {icon}
        <span className="flex-1 truncate">{label}</span>
        {count !== undefined && (
          <span className="ml-auto shrink-0 text-xs text-sidebar-foreground/50 tabular-nums">
            {count}
          </span>
        )}
      </SidebarMenuSubButton>
    </SidebarMenuSubItem>
  );
}
