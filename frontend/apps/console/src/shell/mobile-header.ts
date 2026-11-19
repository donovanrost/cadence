import {
  onScopeDispose,
  computed,
  shallowRef,
  toValue,
  watchEffect,
  type MaybeRefOrGetter,
} from "vue";
import type { RouteLocationRaw } from "vue-router";

/**
 * Small-screen header content a screen asks for (Mobile.md: back · context line over title · UTC).
 * Ignored on desktop. The last registering screen wins; it clears on that screen's unmount.
 */
export type MobileHeader = Readonly<{
  title: string;
  context?: string | undefined;
  back?: RouteLocationRaw | undefined;
}>;

const current = shallowRef<MobileHeader | null>(null);
let owner = 0;

export function useMobileHeader(header: MaybeRefOrGetter<MobileHeader | null>) {
  const id = ++owner;
  let mine = false;
  watchEffect(() => {
    const value = toValue(header);
    current.value = value;
    mine = true;
    owner = id;
  });
  onScopeDispose(() => {
    if (mine && owner === id) current.value = null;
  });
}

export function useCurrentMobileHeader() {
  return computed(() => current.value);
}
