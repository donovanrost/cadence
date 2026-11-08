import { onScopeDispose, ref, watch, type Ref } from "vue";

/** Open/close state for a popover anchored in `root`: Escape and outside clicks close it. */
export function useDisclosure(root: Readonly<Ref<HTMLElement | null>>) {
  const open = ref(false);
  const onPointer = (event: PointerEvent) => {
    if (root.value && event.target instanceof Node && !root.value.contains(event.target))
      open.value = false;
  };
  const onKey = (event: KeyboardEvent) => {
    if (event.key === "Escape") {
      open.value = false;
      root.value?.querySelector<HTMLElement>("[aria-expanded]")?.focus();
    }
  };
  watch(open, (isOpen) => {
    if (isOpen) {
      document.addEventListener("pointerdown", onPointer);
      document.addEventListener("keydown", onKey);
    } else {
      document.removeEventListener("pointerdown", onPointer);
      document.removeEventListener("keydown", onKey);
    }
  });
  onScopeDispose(() => {
    document.removeEventListener("pointerdown", onPointer);
    document.removeEventListener("keydown", onKey);
  });
  return {
    open,
    toggle: () => {
      open.value = !open.value;
    },
    close: () => {
      open.value = false;
    },
  };
}
