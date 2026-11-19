import { readonly, ref, type Ref } from "vue";

/**
 * True below the md breakpoint (48rem = 768px), where the shell switches to the on-call layout.
 * One media-query listener for the app's lifetime; components read the shared ref.
 */
const QUERY = "(max-width: 47.99rem)";
const media =
  typeof window !== "undefined" && "matchMedia" in window ? window.matchMedia(QUERY) : null;
const small = ref(media?.matches ?? false);
media?.addEventListener("change", (event) => {
  small.value = event.matches;
});

export function useSmallScreen(): Readonly<Ref<boolean>> {
  return readonly(small);
}
