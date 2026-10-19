import { cn } from "cn";

// Hand-picked hues keep every tile on the palette; a raw hash lands on muddy olives.
const HUES = [18, 160, 205, 255, 290, 335];
const hueOf = (id: string) =>
  HUES[
    [...id].reduce((sum, char) => sum + char.charCodeAt(0), 0) % HUES.length
  ];

export function CampaignAvatar({
  id,
  name,
  className,
}: {
  id: string;
  name: string;
  className?: string;
}) {
  const hue = hueOf(id);
  return (
    <span
      aria-hidden="true"
      style={{
        background: `linear-gradient(135deg, oklch(0.56 0.13 ${hue}), oklch(0.36 0.11 ${(hue + 40) % 360}))`,
      }}
      className={cn(
        "flex size-8 shrink-0 items-center justify-center rounded-lg font-heading text-sm font-semibold text-white/95 shadow-sm",
        className
      )}
    >
      {name.trim().charAt(0).toUpperCase() || "?"}
    </span>
  );
}
