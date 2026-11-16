import { nextTick, onScopeDispose, ref, type Ref } from "vue";
import { focusFirstConnected, focusLost, refocusFirst } from "@cadence/apogee-ui";

/**
 * a11y A1/A5 for an editor that swaps in place for its opener (Edit → form → Edit, Override →
 * field): `show()` opens it and focuses its first field; `hide()` closes it and returns focus to
 * the opener, else to `after()` (an outcome line), else the page h1, never <body>.
 *
 * An editor that loads before its fields render (a schema read) holds focus on its own box, then
 * hands it to the first field when that appears, unless the user has moved on.
 *
 * Inside `root`, mark the opener `data-swap-opener` and the editor's root `data-swap-editor`. With
 * several swaps in one root, give each a `name` and set both attributes to it. Pass `open` when the
 * open state lives elsewhere (a v-model).
 */
export function useInPlaceSwap(
  root: Readonly<Ref<HTMLElement | null>>,
  { name = "", open = ref(false) }: { name?: string; open?: Ref<boolean> } = {},
) {
  const find = (selector: string) => root.value?.querySelector<HTMLElement>(selector) ?? null;
  const editor = `[data-swap-editor="${name}"]`;
  const field = () => find(`${editor} input, ${editor} textarea, ${editor} select`);
  let waiting: MutationObserver | null = null;
  const stopWaiting = () => {
    waiting?.disconnect();
    waiting = null;
  };
  onScopeDispose(stopWaiting);

  async function show() {
    open.value = true;
    await nextTick();
    const now = field();
    if (now) return now.focus();
    const box = find(editor);
    if (!box) return focusFirstConnected();
    refocusFirst(box);
    stopWaiting();
    waiting = new MutationObserver(() => {
      const later = field();
      if (!later) return;
      stopWaiting();
      if (focusLost() || document.activeElement === box) later.focus();
    });
    waiting.observe(box, { childList: true, subtree: true });
  }

  async function hide(after?: () => HTMLElement | null | undefined) {
    stopWaiting();
    open.value = false;
    await nextTick();
    focusFirstConnected(find(`[data-swap-opener="${name}"]`), after?.());
  }

  return { open, show, hide };
}
