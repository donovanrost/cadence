<script setup lang="ts">
import { onMounted, watch } from "vue";
import ApStatusMark from "./ApStatusMark.vue";
import { announcePolite } from "./lib/announce.ts";

/**
 * States the fact, then one sentence on why / what next. Never an illustration.
 * `announce`: set it where the empty state is the outcome of the person's own search or filter
 * ("No points match"), so it's read without moving focus (a11y B6). Not for a list that's simply
 * empty on first load: that's read with the page.
 */
const props = defineProps<{
  headline: string;
  sentence?: string | undefined;
  /** `off` = not set up (dashed mark). */
  state?: "off" | "stale" | undefined;
  announce?: boolean | undefined;
}>();

const words = () => [props.headline, props.sentence].filter(Boolean).join(" ");
onMounted(() => {
  if (props.announce) announcePolite(words());
});
watch(words, (now) => {
  if (props.announce) announcePolite(now);
});
</script>

<template>
  <div class="flex flex-col items-start gap-2 px-4 py-6">
    <p class="ap-label flex items-center gap-2">
      <ApStatusMark v-if="state" :state="state" />{{ headline }}
    </p>
    <p v-if="sentence" class="m-0 max-w-[60ch] text-base leading-[1.55] text-text-3">
      {{ sentence }}
    </p>
    <div v-if="$slots.default" class="mt-1"><slot /></div>
  </div>
</template>
