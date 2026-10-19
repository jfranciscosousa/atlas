// BlockNote only runs in the browser, so the editor stays out of the main bundle.
// The route loader awaits it, so the page renders it without a loading fallback.
// A separate module keeps the value shared between the route's loader and component chunks.
type Editor = typeof import("./rich-text-editor").default;

let editor: Editor | undefined;

export async function loadEditor() {
  editor = (await import("./rich-text-editor")).default;
}

export function getEditor(): Editor {
  if (!editor) throw new Error("The editor loads before the page renders.");
  return editor;
}
