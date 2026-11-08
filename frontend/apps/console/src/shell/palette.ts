import { onScopeDispose, readonly, ref } from "vue";

/**
 * ⌘K palette open state, shared by the top-bar trigger and the palette (fe-ops, mounted in
 * App.vue). `bindPaletteShortcut` is called once by the shell.
 */
const open = ref(false);

export function usePalette() {
  return {
    open: readonly(open),
    show: () => {
      open.value = true;
    },
    hide: () => {
      open.value = false;
    },
  };
}

const typing = (target: EventTarget | null) =>
  target instanceof HTMLElement &&
  (target.isContentEditable || ["INPUT", "TEXTAREA", "SELECT"].includes(target.tagName));

export function bindPaletteShortcut() {
  const onKey = (event: KeyboardEvent) => {
    const combo = event.key.toLowerCase() === "k" && (event.metaKey || event.ctrlKey);
    const slash = event.key === "/" && !typing(event.target);
    if (combo || slash) {
      event.preventDefault();
      open.value = true;
    }
  };
  window.addEventListener("keydown", onKey);
  onScopeDispose(() => window.removeEventListener("keydown", onKey));
}
