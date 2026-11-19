import { onBeforeUnmount, onMounted, type Ref } from "vue";

const FOCUSABLE =
  'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';

/**
 * a11y A3 (#243, #433's known gap): Tab and Shift+Tab cycle inside a modal that isn't a native
 * <dialog> (the phone Search sheet), never reaching the page behind. Focus that left it (a control
 * that removed itself, such as Show all N or Try again, drops focus to <body>) comes back to its
 * first control on the next Tab.
 */
export function trapTab(root: HTMLElement | null, event: KeyboardEvent): void {
  if (event.key !== "Tab" || !root) return;
  const items = Array.from(root.querySelectorAll<HTMLElement>(FOCUSABLE));
  const first = items[0];
  const last = items.at(-1);
  if (!first || !last) return;
  const active = document.activeElement;
  const inside = active instanceof Node && root.contains(active);
  if (!inside || (event.shiftKey && active === first)) {
    event.preventDefault();
    (inside ? last : first).focus();
  } else if (!event.shiftKey && active === last) {
    event.preventDefault();
    first.focus();
  }
}

/**
 * Listens on the document while the sheet is mounted (capture), not on the sheet: once a focused
 * control removes itself, keydown no longer starts inside the sheet (dashboards, #458).
 */
export function useTabTrap(root: Readonly<Ref<HTMLElement | null>>): void {
  const onKey = (event: KeyboardEvent) => trapTab(root.value, event);
  onMounted(() => document.addEventListener("keydown", onKey, true));
  onBeforeUnmount(() => document.removeEventListener("keydown", onKey, true));
}
