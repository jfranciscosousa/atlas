const FLASH = "oklch(0.78 0.14 75 / 0.45)";
const GIVE_UP_MS = 2500;

const reduced = () => matchMedia("(prefers-reduced-motion: reduce)").matches;

/**
 * Scrolls to a block of the editor in `container` and flashes it. The editor and its tab may
 * still be loading, so this looks again on every frame until the block shows or time runs out.
 * Returns a function that stops the search.
 */
export function revealBlock(container: string, block: string) {
  const selector = `[data-id="${block.replace(/["\\]/g, "\\$&")}"]`;
  const started = performance.now();
  let frame = 0;

  const look = () => {
    const root = document.getElementById(container);
    const outer = root?.querySelector<HTMLElement>(selector);
    // A block in a hidden tab has no box yet.
    if (outer && outer.getClientRects().length > 0) {
      const target =
        outer.querySelector<HTMLElement>(".bn-block-content") ?? outer;
      target.scrollIntoView({
        block: "center",
        behavior: reduced() ? "auto" : "smooth",
      });
      if (!reduced())
        target.animate(
          [{ backgroundColor: FLASH }, { backgroundColor: "transparent" }],
          { duration: 2600, easing: "ease-out" }
        );
      return;
    }
    // The block is gone: the section still opens at its top.
    if (performance.now() - started > GIVE_UP_MS) {
      if (root && root.getClientRects().length > 0)
        root.scrollIntoView({ block: "start", behavior: "auto" });
      return;
    }
    frame = requestAnimationFrame(look);
  };

  frame = requestAnimationFrame(look);
  return () => cancelAnimationFrame(frame);
}
