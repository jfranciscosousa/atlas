import { useState, type ReactNode } from "react";
import {
  ChevronsUpDownIcon,
  CompassIcon,
  LogOutIcon,
  LayoutGridIcon,
  SettingsIcon,
  UserIcon,
} from "lucide-react";
import { Link, useRouter, useRouterState } from "@tanstack/react-router";
import { useQueryClient } from "@tanstack/react-query";

import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarGroup,
  SidebarGroupContent,
  SidebarGroupLabel,
  SidebarHeader,
  SidebarInset,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarProvider,
  SidebarTrigger,
  useSidebar,
} from "./ui/sidebar";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "./ui/dropdown-menu";
import { Avatar, AvatarFallback, AvatarImage } from "./ui/avatar";
import { NewCampaignButton } from "./new-campaign-button";
import { CampaignNav } from "./campaign-nav";
import { sessionRequest } from "../lib/auth";
import { useProfile } from "../hooks/use-profile";
import { useCampaignsList } from "../hooks/use-campaigns";

type ShellUser = { id: string; email: string };

function Brand() {
  return (
    <Link
      to="/campaigns"
      className="flex items-center gap-2.5 rounded-lg px-2 py-1.5 font-heading text-lg font-semibold tracking-wide text-sidebar-accent-foreground outline-none focus-visible:ring-2 focus-visible:ring-sidebar-ring"
    >
      <span className="flex size-8 items-center justify-center rounded-lg bg-sidebar-primary text-sidebar-primary-foreground">
        <CompassIcon aria-hidden="true" className="size-5" />
      </span>
      Atlas
    </Link>
  );
}

function UserMenu({ user }: { user: ShellUser }) {
  const queryClient = useQueryClient();
  const router = useRouter();
  const { isMobile } = useSidebar();
  const profile = useProfile(user.id).data;
  const [signingOut, setSigningOut] = useState(false);
  const name = profile.displayName ?? user.email;

  async function signOut() {
    setSigningOut(true);
    try {
      await sessionRequest("/api/session", {
        method: "DELETE",
        queryClient,
      });
      // The live-editing socket loads on demand: most sessions never open one.
      void import("../lib/collab-socket").then(m => m.closeCollabSocket());
      await queryClient.cancelQueries();
      queryClient.clear();
      await router.invalidate();
    } finally {
      setSigningOut(false);
    }
  }

  return (
    <SidebarMenu>
      <SidebarMenuItem>
        <DropdownMenu>
          <DropdownMenuTrigger
            render={
              <SidebarMenuButton
                id="user-menu"
                size="lg"
                className="data-popup-open:bg-sidebar-accent"
              />
            }
          >
            <Avatar>
              <AvatarImage src={profile.avatar ?? undefined} alt="" />
              <AvatarFallback>
                {name.trim().charAt(0).toUpperCase()}
              </AvatarFallback>
            </Avatar>
            <span className="grid min-w-0 flex-1 text-left leading-tight">
              <span
                id="current-user-name"
                className="truncate text-sm font-medium"
              >
                {name}
              </span>
              <span
                id="current-user-email"
                className="truncate text-xs text-sidebar-foreground/60"
              >
                {user.email}
              </span>
            </span>
            <ChevronsUpDownIcon
              aria-hidden="true"
              className="ml-auto size-4 text-sidebar-foreground/60"
            />
          </DropdownMenuTrigger>
          <DropdownMenuContent
            side={isMobile ? "bottom" : "right"}
            align="end"
            className="min-w-56"
          >
            <DropdownMenuGroup>
              <DropdownMenuLabel>{user.email}</DropdownMenuLabel>
            </DropdownMenuGroup>
            <DropdownMenuItem id="edit-profile" render={<Link to="/profile" />}>
              <UserIcon aria-hidden="true" />
              Profile
            </DropdownMenuItem>
            <DropdownMenuItem id="settings" render={<Link to="/settings" />}>
              <SettingsIcon aria-hidden="true" />
              Settings
            </DropdownMenuItem>
            <DropdownMenuSeparator />
            <DropdownMenuItem
              id="sign-out"
              disabled={signingOut}
              onClick={() => void signOut()}
            >
              <LogOutIcon aria-hidden="true" />
              Sign out
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </SidebarMenuItem>
    </SidebarMenu>
  );
}

function AppSidebar({ user }: { user: ShellUser }) {
  const campaigns = useCampaignsList(user.id).data;
  const pathname = useRouterState({ select: state => state.location.pathname });
  const { isMobile, setOpenMobile } = useSidebar();
  const closeOnMobile = () => isMobile && setOpenMobile(false);

  return (
    <Sidebar>
      <SidebarHeader className="gap-3 p-3">
        <Brand />
        <NewCampaignButton
          userId={user.id}
          variant="secondary"
          className="w-full justify-start bg-sidebar-accent text-sidebar-accent-foreground hover:bg-sidebar-accent/70"
        />
      </SidebarHeader>
      <SidebarContent>
        <SidebarGroup>
          <SidebarGroupContent>
            <SidebarMenu>
              <SidebarMenuItem>
                <SidebarMenuButton
                  isActive={pathname === "/campaigns"}
                  render={<Link to="/campaigns" onClick={closeOnMobile} />}
                >
                  <LayoutGridIcon aria-hidden="true" />
                  All campaigns
                </SidebarMenuButton>
              </SidebarMenuItem>
            </SidebarMenu>
          </SidebarGroupContent>
        </SidebarGroup>
        <SidebarGroup>
          <SidebarGroupLabel>Your campaigns</SidebarGroupLabel>
          <SidebarGroupContent>
            <SidebarMenu id="sidebar-campaigns">
              {campaigns.length === 0 && (
                <li className="px-2 py-1.5 text-sm text-sidebar-foreground/50">
                  Nothing here yet.
                </li>
              )}
              {campaigns.map(campaign => (
                <CampaignNav
                  key={campaign.id}
                  campaign={campaign}
                  pathname={pathname}
                  onNavigate={closeOnMobile}
                />
              ))}
            </SidebarMenu>
          </SidebarGroupContent>
        </SidebarGroup>
      </SidebarContent>
      <SidebarFooter className="border-t border-sidebar-border p-2">
        <UserMenu user={user} />
      </SidebarFooter>
    </Sidebar>
  );
}

export function AppShell({
  user,
  children,
}: {
  user: ShellUser;
  children: ReactNode;
}) {
  return (
    <SidebarProvider>
      <AppSidebar user={user} />
      <SidebarInset>
        <div className="sticky top-0 z-20 flex h-12 items-center gap-2 border-b bg-background/85 px-3 backdrop-blur">
          <SidebarTrigger aria-label="Toggle navigation" />
          <span className="font-heading text-base font-semibold md:hidden">
            Atlas
          </span>
        </div>
        <main className="mx-auto w-full max-w-5xl flex-1 px-4 py-8 sm:px-8 lg:py-12">
          {children}
        </main>
      </SidebarInset>
    </SidebarProvider>
  );
}
