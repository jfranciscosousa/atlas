import {
  useEffect,
  useState,
  type KeyboardEvent,
  type MouseEvent,
  type ReactNode,
} from "react";
import {
  ArrowRightIcon,
  BookOpenTextIcon,
  CalendarDaysIcon,
  CornerDownLeftIcon,
  LayoutGridIcon,
  ScrollTextIcon,
  SearchIcon,
  SettingsIcon,
  UserIcon,
  UsersIcon,
} from "lucide-react";
import { cn } from "cn";
import { useRouter } from "@tanstack/react-router";

import { Spinner } from "./ui/spinner";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogTitle,
} from "./ui/dialog";
import { CampaignAvatar } from "./campaign-avatar";
import {
  KIND_LABELS,
  groupHits,
  highlight,
  hitPath,
  queryTerms,
  sectionLabel,
  type SearchHit,
  type SearchKind,
} from "../lib/search";
import { useSearch } from "../hooks/use-search";
import { useCampaignsList } from "../hooks/use-campaigns";

const QUERY_MAX_LENGTH = 200;
const DEBOUNCE_MS = 150;

const KIND_ICONS: Record<Exclude<SearchKind, "campaign">, typeof UsersIcon> = {
  session: CalendarDaysIcon,
  character: UsersIcon,
  note: BookOpenTextIcon,
  player_log: ScrollTextIcon,
};

const PAGES = [
  { label: "All campaigns", path: "/campaigns", icon: LayoutGridIcon },
  { label: "Your profile", path: "/profile", icon: UserIcon },
  { label: "Settings", path: "/settings", icon: SettingsIcon },
];

type Item = {
  key: string;
  path: string;
  title: string;
  /** Campaign hits and campaigns in the jump list show an avatar. */
  campaign?: { id: string; name: string };
  icon?: typeof UsersIcon;
  hit?: SearchHit;
};

type Group = { label: string; items: Item[] };

const campaignItem = (campaign: { id: string; name: string }): Item => ({
  key: `jump:${campaign.id}`,
  path: `/campaigns/${campaign.id}`,
  title: campaign.name,
  campaign,
});

function hitItem(hit: SearchHit): Item {
  return {
    key: `${hit.kind}:${hit.id}`,
    path: hitPath(hit),
    title: hit.title,
    hit,
    ...(hit.kind === "campaign"
      ? { campaign: { id: hit.id, name: hit.title } }
      : { icon: KIND_ICONS[hit.kind] }),
  };
}

function useDebounced(value: string, delay: number) {
  const [debounced, setDebounced] = useState(value);
  useEffect(() => {
    const timer = setTimeout(() => setDebounced(value), delay);
    return () => clearTimeout(timer);
  }, [value, delay]);
  return debounced;
}

function Marked({ text, terms }: { text: string; terms: string[] }) {
  return (
    <>
      {highlight(text, terms).map((part, index) =>
        part.match ? (
          <mark
            key={index}
            className="rounded-sm bg-gold/30 px-0.5 text-inherit"
          >
            {part.text}
          </mark>
        ) : (
          part.text
        )
      )}
    </>
  );
}

function Kbd({ children }: { children: ReactNode }) {
  return (
    <kbd className="inline-flex h-5 min-w-5 items-center justify-center rounded-md border bg-muted px-1 font-sans text-[0.6875rem] font-medium text-muted-foreground">
      {children}
    </kbd>
  );
}

function ResultRow({
  item,
  terms,
  active,
  onActivate,
  onOpen,
}: {
  item: Item;
  terms: string[];
  active: boolean;
  onActivate: () => void;
  onOpen: (event: MouseEvent<HTMLAnchorElement>) => void;
}) {
  const { hit } = item;
  const Icon = item.icon;
  const section = hit?.sections[0];
  const snippet = section?.blocks[0]?.text;

  return (
    <a
      id={`palette-${item.key}`}
      role="option"
      aria-selected={active}
      href={item.path}
      tabIndex={-1}
      onMouseMove={() => !active && onActivate()}
      onClick={onOpen}
      className={cn(
        "flex gap-3 rounded-xl px-2.5 py-2 text-sm outline-none",
        snippet ? "items-start" : "items-center",
        active && "bg-accent text-accent-foreground"
      )}
    >
      {item.campaign ? (
        <CampaignAvatar
          id={item.campaign.id}
          name={item.campaign.name}
          className="size-8 rounded-lg"
        />
      ) : (
        Icon && (
          <span
            aria-hidden="true"
            className="flex size-8 shrink-0 items-center justify-center rounded-lg bg-muted text-muted-foreground"
          >
            <Icon className="size-4" />
          </span>
        )
      )}
      <span className="grid min-w-0 flex-1 gap-0.5">
        <span className="flex items-baseline gap-2">
          <span className="truncate font-medium">
            <Marked text={item.title} terms={terms} />
          </span>
          {hit && hit.kind !== "campaign" && (
            <span className="ml-auto max-w-[40%] shrink-0 truncate text-xs text-muted-foreground">
              {hit.campaign_name}
            </span>
          )}
        </span>
        {snippet && section && (
          <span className="line-clamp-2 text-xs/relaxed text-muted-foreground">
            <span className="mr-1.5 rounded-md bg-secondary px-1.5 py-px text-[0.6875rem] font-medium text-secondary-foreground">
              {sectionLabel(section.section)}
            </span>
            <Marked text={snippet} terms={terms} />
          </span>
        )}
      </span>
      <ArrowRightIcon
        aria-hidden="true"
        className={cn(
          "size-3.5 shrink-0 text-muted-foreground",
          snippet && "mt-2",
          !active && "invisible"
        )}
      />
    </a>
  );
}

function PaletteBody({
  userId,
  onClose,
}: {
  userId: string;
  onClose: () => void;
}) {
  const router = useRouter();
  const campaigns = useCampaignsList(userId).data;
  const [input, setInput] = useState("");
  const [activeKey, setActiveKey] = useState<string>();

  const query = input.trim().slice(0, QUERY_MAX_LENGTH);
  const debounced = useDebounced(query, DEBOUNCE_MS);
  const terms = queryTerms(query);
  const searching = terms.length > 0;
  const search = useSearch(searching ? debounced : "");
  const waiting = searching && (debounced !== query || search.isFetching);

  const groups: Group[] = [];
  if (searching) {
    for (const group of groupHits(search.data?.hits ?? []))
      groups.push({
        label: KIND_LABELS[group.kind],
        items: group.hits.map(hitItem),
      });
    const pages = PAGES.filter(page =>
      terms.every(term => page.label.toLowerCase().includes(term))
    );
    if (pages.length > 0)
      groups.push({
        label: "Pages",
        items: pages.map(page => ({
          key: `page:${page.path}`,
          path: page.path,
          title: page.label,
          icon: page.icon,
        })),
      });
  } else {
    if (campaigns.length > 0)
      groups.push({ label: "Jump to", items: campaigns.map(campaignItem) });
    groups.push({
      label: "Pages",
      items: PAGES.map(page => ({
        key: `page:${page.path}`,
        path: page.path,
        title: page.label,
        icon: page.icon,
      })),
    });
  }

  const items = groups.flatMap(group => group.items);
  const active = items.find(item => item.key === activeKey) ?? items[0];

  useEffect(() => {
    if (!active) return;
    document
      .getElementById(`palette-${active.key}`)
      ?.scrollIntoView({ block: "nearest" });
  }, [active?.key]);

  function open(item: Item, newTab = false) {
    if (newTab) {
      window.open(item.path, "_blank", "noopener");
      return;
    }
    onClose();
    router.history.push(item.path);
  }

  function onKeyDown(event: KeyboardEvent<HTMLInputElement>) {
    if (event.nativeEvent.isComposing) return;
    const index = active ? items.indexOf(active) : -1;
    const move = (to: number) => {
      event.preventDefault();
      if (items.length > 0)
        setActiveKey(items[(to + items.length) % items.length].key);
    };

    if (event.key === "ArrowDown") move(index + 1);
    else if (event.key === "ArrowUp") move(index - 1);
    else if (event.key === "Home" && event.ctrlKey) move(0);
    else if (event.key === "End" && event.ctrlKey) move(items.length - 1);
    else if (event.key === "Enter" && active) {
      event.preventDefault();
      open(active, event.metaKey || event.ctrlKey);
    }
  }

  const failed = searching && search.isError;
  const empty = searching && !waiting && !failed && items.length === 0;

  return (
    <>
      <div className="flex items-center gap-3 border-b px-4">
        <SearchIcon
          aria-hidden="true"
          className="size-4 shrink-0 text-muted-foreground"
        />
        <input
          autoFocus
          type="text"
          role="combobox"
          aria-expanded="true"
          aria-controls="palette-results"
          aria-activedescendant={active && `palette-${active.key}`}
          aria-label="Search"
          autoComplete="off"
          autoCorrect="off"
          spellCheck={false}
          maxLength={QUERY_MAX_LENGTH}
          placeholder="Search campaigns, sessions, characters, notes…"
          value={input}
          onChange={event => setInput(event.target.value)}
          onKeyDown={onKeyDown}
          className="h-13 min-w-0 flex-1 bg-transparent text-base outline-none placeholder:text-muted-foreground md:text-sm"
        />
        {waiting && <Spinner className="shrink-0 text-muted-foreground" />}
        <Kbd>Esc</Kbd>
      </div>

      <div
        id="palette-results"
        role="listbox"
        aria-label="Results"
        className="max-h-[min(55vh,26rem)] overflow-y-auto overscroll-contain p-2"
      >
        {groups.map(group => (
          <div
            key={group.label}
            role="group"
            aria-label={group.label}
            className="pb-1"
          >
            <div
              aria-hidden="true"
              className="px-2.5 pt-2 pb-1 text-xs font-medium text-muted-foreground"
            >
              {group.label}
            </div>
            {group.items.map(item => (
              <ResultRow
                key={item.key}
                item={item}
                terms={terms}
                active={item.key === active?.key}
                onActivate={() => setActiveKey(item.key)}
                onOpen={event => {
                  if (
                    event.metaKey ||
                    event.ctrlKey ||
                    event.shiftKey ||
                    event.button !== 0
                  )
                    return;
                  event.preventDefault();
                  open(item);
                }}
              />
            ))}
          </div>
        ))}

        {failed && (
          <p
            role="alert"
            className="px-3 py-8 text-center text-sm text-destructive"
          >
            {search.error.message}
          </p>
        )}
        {empty && (
          <p className="px-3 py-8 text-center text-sm text-muted-foreground">
            No matches for “{query}”.
          </p>
        )}
        {searching && waiting && !failed && items.length === 0 && (
          <p className="px-3 py-8 text-center text-sm text-muted-foreground">
            Searching…
          </p>
        )}
      </div>

      <div className="flex items-center gap-4 border-t bg-muted/40 px-4 py-2 text-xs text-muted-foreground">
        <span className="flex items-center gap-1.5">
          <Kbd>↑</Kbd>
          <Kbd>↓</Kbd>
          Move
        </span>
        <span className="flex items-center gap-1.5">
          <Kbd>
            <CornerDownLeftIcon aria-hidden="true" className="size-3" />
          </Kbd>
          Open
        </span>
        {search.data?.more && searching && (
          <span className="ml-auto">
            More matches exist. Add a word to narrow.
          </span>
        )}
      </div>
    </>
  );
}

/** Opens with Ctrl+K or Cmd+K from any page. `open` and `onOpenChange` belong to the shell. */
export function CommandPalette({
  userId,
  open,
  onOpenChange,
}: {
  userId: string;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  useEffect(() => {
    function onKeyDown(event: globalThis.KeyboardEvent) {
      if (
        event.key.toLowerCase() !== "k" ||
        !(event.metaKey || event.ctrlKey) ||
        event.altKey ||
        event.shiftKey
      )
        return;
      // The editors bind this key to links. Search wins: it works from every page.
      event.preventDefault();
      event.stopPropagation();
      onOpenChange(!open);
    }
    document.addEventListener("keydown", onKeyDown, true);
    return () => document.removeEventListener("keydown", onKeyDown, true);
  }, [open, onOpenChange]);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent
        showCloseButton={false}
        className="top-[10vh] translate-y-0 gap-0 overflow-hidden rounded-2xl p-0 sm:max-w-xl"
      >
        <DialogTitle className="sr-only">Search</DialogTitle>
        <DialogDescription className="sr-only">
          Search every campaign, session, character, note and player log that
          you may read. Use the arrow keys to choose a result and Enter to open
          it.
        </DialogDescription>
        <PaletteBody userId={userId} onClose={() => onOpenChange(false)} />
      </DialogContent>
    </Dialog>
  );
}
