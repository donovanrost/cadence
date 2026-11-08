import { computed, onScopeDispose, readonly, ref } from "vue";

/**
 * ⌘K palette open state, shared by the top-bar trigger and the palette (fe-ops, mounted in
 * App.vue). `bindPaletteShortcut` is called once by the shell.
 */
const open = ref(false);
/** True once a palette component is mounted; until then the trigger and shortcut stay hidden. */
const registered = ref(0);

export function usePalette() {
  return {
    open: readonly(open),
    available: computed(() => registered.value > 0),
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
    if ((combo || slash) && registered.value > 0) {
      event.preventDefault();
      open.value = true;
    }
  };
  window.addEventListener("keydown", onKey);
  onScopeDispose(() => window.removeEventListener("keydown", onKey));
}

/** Called by the palette component's setup; unregisters with its scope. */
export function registerPalette() {
  registered.value += 1;
  onScopeDispose(() => {
    registered.value -= 1;
    open.value = false;
  });
}
