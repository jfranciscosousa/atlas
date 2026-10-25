import { createContext, useContext } from "react";

/**
 * True inside Preview as player. The GM's requests return what only the GM reads, so a page in
 * preview asks for the player's view, and its mentions and links follow.
 */
export const PreviewContext = createContext(false);

export const usePreview = () => useContext(PreviewContext);
