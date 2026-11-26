<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from "vue";
import type { RouteLocationRaw } from "vue-router";
import { revealInline } from "./lib/reveal.ts";

/** Section navigation between routes (links, not ARIA tabs). Looks like ApSegmented `tabs`. */
export type ApTabLink = Readonly<{
  key: string;
  label: string;
  to: RouteLocationRaw;
  count?: number;
}>;
const props = defineProps<{ links: readonly ApTabLink[]; active: string; label: string }>();
/**
 * On a narrow screen the strip scrolls sideways; the active link is kept in view (ux U94), and so is
 * the link that has keyboard focus (#189: Tab stopped on a link cut off at the edge). Only the strip
 * scrolls (scrollLeft), never the page, so a re-mount far down a long page can't jump (lead).
 */
const nav = ref<HTMLElement | null>(null);
/** The edge fade's width: a link is in view only when it clears the fade too. */
const FADE = 24;
/** revealInline stops at scrollLeft 0: the first link has no fade to clear. */
function reveal(link: HTMLElement) {
  const strip = nav.value;
  if (!strip) return;
  revealInline(strip, link, { start: FADE, end: FADE });
  measure();
}
function showActive() {
  void nextTick(() => {
    const link = nav.value?.querySelector<HTMLElement>('[aria-current="page"]');
    if (link) reveal(link);
  });
}
function showFocused(event: FocusEvent) {
  if (event.target instanceof HTMLElement) reveal(event.target);
}
/*
 * flex-none: the strip scrolls sideways (overflow-x-auto), so in a screen's flex column it has no
 * automatic minimum height and would shrink to nothing when the screen overflows; the next panel
 * then sits over its links (#189: Telemetry at 390, T1 Points over Explore and Dashboards).
 */
/**
 * ux #349: a strip cut off on a narrow screen shows that it scrolls. The edge with more links
 * behind it fades, and the fade goes once that end is reached.
 */
const more = ref<Readonly<{ left: boolean; right: boolean }>>({ left: false, right: false });
function measure() {
  const strip = nav.value;
  if (!strip) return;
  more.value = {
    left: strip.scrollLeft > 1,
    right: strip.scrollLeft + strip.clientWidth < strip.scrollWidth - 1,
  };
}
const fade = computed(() => {
  const { left, right } = more.value;
  if (left && right)
    return "[mask-image:linear-gradient(to_right,transparent,#000_24px,#000_calc(100%-24px),transparent)]";
  if (right) return "[mask-image:linear-gradient(to_right,#000_calc(100%-24px),transparent)]";
  if (left) return "[mask-image:linear-gradient(to_right,transparent,#000_24px)]";
  return "";
});
// A resize (a rotated phone, a narrowed window) keeps the active link in view and the fade right (ux #352).
onMounted(() => {
  showActive();
  window.addEventListener("resize", showActive);
});
onBeforeUnmount(() => window.removeEventListener("resize", showActive));
watch(() => props.active, showActive);
// New or relabelled links change the strip's width (fe-setup's #352 review).
watch(() => props.links, showActive, { deep: true });
</script>

<template>
  <nav
    ref="nav"
    :aria-label="label"
    class="flex flex-none overflow-x-auto border-b border-hairline"
    :class="fade"
    @scroll.passive="measure"
    @focusin="showFocused"
  >
    <RouterLink
      v-for="link in links"
      :key="link.key"
      :to="link.to"
      :aria-current="link.key === active ? 'page' : undefined"
      class="flex h-9 flex-none items-center gap-2 whitespace-nowrap max-md:hit-44 border-r border-hairline px-4 font-display text-md font-semibold tracking-tag uppercase no-underline last:border-r-0"
      :class="
        link.key === active
          ? 'bg-raised text-readout shadow-[inset_0_-2px_0_var(--color-readout)]'
          : 'text-text-3 hover:text-readout'
      "
    >
      <!-- The space keeps the count a separate word in the link's name: "Released 0", not "Released0". -->
      {{ link.label }}
      <span v-if="link.count !== undefined" class="font-mono text-xs">{{ link.count }}</span>
    </RouterLink>
  </nav>
</template>
