import {
  FlagIcon,
  GemIcon,
  MapPinIcon,
  PawPrintIcon,
  UserRoundIcon,
  WaypointsIcon,
} from "lucide-react";

import type { EntryKind } from "../lib/entry-kinds";

export const ENTRY_ICONS: Record<EntryKind, typeof UserRoundIcon> = {
  npc: UserRoundIcon,
  location: MapPinIcon,
  faction: FlagIcon,
  item: GemIcon,
  creature: PawPrintIcon,
  plot: WaypointsIcon,
};
