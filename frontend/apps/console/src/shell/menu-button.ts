import { nextTick, type Ref } from "vue";
import { useDisclosure } from "./disclosure.ts";

/**
 * The menu button (design-language §6; ux): every ⋯ and the account menu. The trigger carries
 * aria-haspopup="menu" and aria-expanded; the popup is role="menu" with role="menuitem" items.
 * Opening focuses the first item (↑ on the trigger: the last); ↑/↓ cycle, Home/End jump; disabled
 * items stay focusable (aria-disabled, their reason as description), never skipped, so the reason
 * is reachable. Esc closes and returns focus to the trigger (useDisclosure); Tab closes and lets
 * focus move on. Outside clicks close it.
 */
export function useMenuButton(root: Readonly<Ref<HTMLElement | null>>) {
  const { open, close } = useDisclosure(root);
  const items = () => [...(root.value?.querySelectorAll<HTMLElement>('[role="menuitem"]') ?? [])];
  function focusAt(index: number) {
    const list = items();
    if (list.length) list[(index + list.length) % list.length]?.focus();
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
  /** On the trigger: ↓ opens on the first item, ↑ on the last. */
  function onTriggerKey(event: KeyboardEvent) {
    if (event.key !== "ArrowDown" && event.key !== "ArrowUp") return;
    event.preventDefault();
    void show(event.key === "ArrowDown" ? "first" : "last");
  }
  /** Inside the menu: ↑/↓ cycle, Home/End jump, Tab closes and lets focus move on. */
  function onMenuKey(event: KeyboardEvent) {
    const list = items();
    const at = list.findIndex((item) => item === document.activeElement);
    const next: Readonly<Record<string, number>> = {
      ArrowDown: at + 1,
      ArrowUp: at - 1,
      Home: 0,
      End: list.length - 1,
    };
    if (event.key === "Tab") return close();
    const target = next[event.key];
    if (target === undefined) return;
    event.preventDefault();
    focusAt(target);
  }
  return { open, toggle, close, onTriggerKey, onMenuKey };
}
