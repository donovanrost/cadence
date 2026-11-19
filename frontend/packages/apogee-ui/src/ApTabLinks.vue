<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from "vue";
import type { RouteLocationRaw } from "vue-router";

/** Section navigation between routes (links, not ARIA tabs). Looks like ApSegmented `tabs`. */
export type ApTabLink = Readonly<{
  key: string;
  label: string;
  to: RouteLocationRaw;
  count?: number;
}>;
const props = defineProps<{ links: readonly ApTabLink[]; active: string; label: string }>();
/**
 * On a narrow screen the strip scrolls sideways; the active link is kept in view (ux U94). Only the
 * strip scrolls (scrollLeft), never the page, so a re-mount far down a long page can't jump (lead).
 */
const nav = ref<HTMLElement | null>(null);
function showActive() {
  void nextTick(() => {
    const strip = nav.value;
    const link = strip?.querySelector<HTMLElement>('[aria-current="page"]');
    if (!strip || !link) return;
    const box = strip.getBoundingClientRect();
    const at = link.getBoundingClientRect();
    if (at.left < box.left) strip.scrollLeft += at.left - box.left;
    else if (at.right > box.right) strip.scrollLeft += at.right - box.right;
    measure();
  });
}
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
onMounted(() => {
  showActive();
  window.addEventListener("resize", measure);
});
onBeforeUnmount(() => window.removeEventListener("resize", measure));
watch(() => props.active, showActive);
</script>

<template>
  <nav
    ref="nav"
    :aria-label="label"
    class="flex overflow-x-auto border-b border-hairline"
    :class="fade"
    @scroll.passive="measure"
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
      {{ link.label
      }}<span v-if="link.count !== undefined" class="font-mono text-xs">{{ link.count }}</span>
    </RouterLink>
  </nav>
</template>
