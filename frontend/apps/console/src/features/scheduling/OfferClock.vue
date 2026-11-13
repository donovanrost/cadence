<script setup lang="ts">
import { ref } from "vue";
import { useDisclosure } from "@/shell/index.ts";
import type { OfferClock } from "./offer-clock.ts";

/**
 * K1 header clock (ux): `NEXT OFFER EXPIRES T−… · KSAT`. Hover, focus or a click opens the
 * detail; the pass in it selects that bar in B.
 */
defineProps<{ clock: OfferClock }>();
const emit = defineEmits<{ select: [snapshotId: string] }>();
const root = ref<HTMLElement | null>(null);
const { open, toggle, close } = useDisclosure(root);
const detailId = `offer-clock-${Math.random().toString(36).slice(2, 9)}`;
function pick(id: string) {
  emit("select", id);
  close();
}
</script>

<template>
  <div ref="root" class="relative flex items-center" @mouseleave="close">
    <button
      type="button"
      class="cursor-pointer border-0 bg-transparent px-2 font-mono text-sm font-medium uppercase tabular"
      :class="clock.tone === 'caution' ? 'text-caution-text' : 'text-readout'"
      :aria-expanded="open"
      :aria-controls="detailId"
      @click="toggle"
      @mouseenter="open = true"
      @focus="open = true"
    >
      {{ clock.label }}
    </button>
    <div
      v-show="open"
      :id="detailId"
      class="absolute top-full right-0 z-40 mt-1 flex w-[360px] max-w-[calc(100vw-32px)] flex-col gap-2 border border-line bg-raised p-3 text-md text-text-2"
    >
      <p class="m-0">
        <template v-if="clock.snapshotId && clock.passText">
          {{ clock.lead
          }}<button
            type="button"
            class="cursor-pointer border-0 bg-transparent p-0 font-mono text-readout underline"
            @click="pick(clock.snapshotId)"
          >
            {{ clock.passText }}</button
          >{{ clock.tail }}
        </template>
        <template v-else>{{ clock.detail }}</template>
      </p>
      <p v-if="clock.providers" class="m-0 font-mono text-sm text-text-3 tabular">
        {{ clock.providers }}
      </p>
      <p v-if="clock.more" class="m-0 text-sm text-caution-text">{{ clock.more }}</p>
    </div>
  </div>
</template>
