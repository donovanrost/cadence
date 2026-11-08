<script setup lang="ts">
import { computed } from "vue";
import ApStatusMark from "./ApStatusMark.vue";
import { stateTextClass, stateWord, type OpState } from "./status.ts";

const props = withDefaults(
  defineProps<{
    /** Omit for a neutral tag. */
    state?: OpState | undefined;
    /** Defaults to the state's word; slot content overrides both. */
    label?: string | undefined;
    size?: "standard" | "tile" | undefined;
  }>(),
  { size: "standard" },
);

const text = computed(() => props.label ?? (props.state ? stateWord(props.state) : ""));
const tone = computed(() => (props.state ? stateTextClass(props.state) : "text-text-3"));
</script>

<template>
  <span
    class="inline-flex items-center gap-[7px] border border-current px-[9px] font-display text-md font-semibold tracking-tag whitespace-nowrap uppercase"
    :class="[tone, size === 'tile' ? 'h-[22px]' : 'h-6']"
  >
    <ApStatusMark v-if="state && state !== 'neutral'" :state="state" />
    <slot>{{ text }}</slot>
  </span>
</template>
