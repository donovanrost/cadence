import { nextTick, onScopeDispose, ref, watch, type InjectionKey, type Ref } from "vue";

/**
 * The WAI-ARIA menu button (design-language §6): every `⋯` and the account menu.
 *
 * - The trigger carries aria-haspopup="menu" and aria-expanded. Opening focuses the first item
 *   (↓ on the trigger: the first; ↑: the last).
 * - Inside the menu ↑/↓ cycle and Home/End jump. Disabled items stay focusable (aria-disabled, their
 *   reason as description), never skipped, so the reason is reachable.
 * - Esc closes and returns focus to the trigger. Tab closes and lets focus move on. A click outside
 *   closes it.
 */
export function useMenuButton(
  root: Readonly<Ref<HTMLElement | null>>,
  trigger: Readonly<Ref<HTMLElement | null>>,
) {
  const open = ref(false);
  const items = () => [...(root.value?.querySelectorAll<HTMLElement>('[role="menuitem"]') ?? [])];
  function focusAt(index: number) {
    const list = items();
    if (list.length) list[(index + list.length) % list.length]?.focus();
  }
  function close() {
    open.value = false;
  }
  /** Close and give focus back to the trigger: Esc, and every chosen item. */
  function dismiss() {
    close();
    trigger.value?.focus();
  }
  async function show(first: "first" | "last" = "first") {
    open.value = true;
    await nextTick();
    focusAt(first === "first" ? 0 : -1);
  }
  function toggle() {
    if (open.value) close();
    else void show();
  }
  /** On the trigger: ↓ opens on the first item, ↑ on the last; Esc closes an open menu. */
  function onTriggerKey(event: KeyboardEvent) {
    if (event.key === "Escape" && open.value) {
      event.preventDefault();
      dismiss();
      return;
    }
    if (event.key !== "ArrowDown" && event.key !== "ArrowUp") return;
    event.preventDefault();
    void show(event.key === "ArrowDown" ? "first" : "last");
  }
  /** Inside the menu: ↑/↓ cycle, Home/End jump, Esc returns to the trigger, Tab moves on. */
  function onMenuKey(event: KeyboardEvent) {
    if (event.key === "Tab") return close();
    if (event.key === "Escape") {
      event.preventDefault();
      event.stopPropagation();
      return dismiss();
    }
    const list = items();
    const at = list.findIndex((item) => item === document.activeElement);
    // keyed-by-text: KeyboardEvent.key values, the DOM's own strings (looked up by event.key)
    const next: Readonly<Record<string, number>> = {
      ArrowDown: at + 1,
      ArrowUp: at - 1,
      Home: 0,
      End: list.length - 1,
    };
    const target = next[event.key];
    if (target === undefined) return;
    event.preventDefault();
    focusAt(target);
  }
  const onPointer = (event: PointerEvent) => {
    if (root.value && event.target instanceof Node && !root.value.contains(event.target)) close();
  };
  watch(open, (isOpen) => {
    if (isOpen) document.addEventListener("pointerdown", onPointer);
    else document.removeEventListener("pointerdown", onPointer);
  });
  onScopeDispose(() => document.removeEventListener("pointerdown", onPointer));
  return { open, toggle, close, dismiss, onTriggerKey, onMenuKey };
}

/** What an ApMenuItem needs from its ApMenuButton: close the menu and hand focus back. */
export type ApMenuContext = { dismiss: () => void };
export const apMenuKey: InjectionKey<ApMenuContext> = Symbol("ApMenu");
