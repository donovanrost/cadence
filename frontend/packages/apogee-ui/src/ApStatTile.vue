<script setup lang="ts">
import { computed } from "vue";
import { formatCount } from "./lib/format.ts";
import { stateInsetClass, stateTextClass, type OpState } from "./status.ts";

/**
 * One stat. `value: null` means unknown and renders an em dash with "unknown" for assistive
 * tech: every number is real or the tile says it doesn't know.
 */
const props = withDefaults(
  defineProps<{
    label: string;
    value: number | string | null;
    denominator?: number | undefined;
    /** Unit after the value, e.g. `V`, drawn like the denominator. */
    unit?: string | undefined;
    caption?: string | undefined;
    state?: OpState | undefined;
    /** Tint the caption with the tile's own state (it's the call to action). */
    captionTinted?: boolean | undefined;
    /** Tint the caption with a different state than the value, e.g. "2 await your GO" in caution. */
    captionState?: OpState | undefined;
    compact?: boolean | undefined;
  }>(),
  { state: "neutral", captionTinted: false, compact: true },
);

const display = computed(() =>
  typeof props.value === "number" ? formatCount(props.value) : props.value,
);
const valueTone = computed(() =>
  props.state === "nominal" || props.state === "neutral"
    ? "text-readout"
    : stateTextClass(props.state),
);
</script>

<template>
  <div
    class="flex flex-col bg-panel"
    :class="[compact ? 'gap-1 px-3.5 py-2.5' : 'gap-1.5 px-4 py-3.5', stateInsetClass(state)]"
  >
    <span class="ap-label">{{ label }}</span>
    <span
      class="font-sans leading-none font-medium tracking-tight tabular"
      :class="[compact ? 'text-[26px]' : 'text-[30px]', valueTone]"
    >
      <template v-if="display !== null">
        {{ display
        }}<span v-if="denominator !== undefined" class="text-base text-text-4"
          >/{{ formatCount(denominator) }}</span
        ><span v-if="unit" class="ml-1 text-base text-text-4">{{ unit }}</span>
      </template>
      <template v-else
        ><span aria-hidden="true" class="text-text-4">—</span
        ><span class="sr-only">unknown</span></template
      >
    </span>
    <span
      v-if="caption"
      class="text-sm"
      :class="
        captionState
          ? stateTextClass(captionState)
          : captionTinted
            ? stateTextClass(state)
            : 'text-text-3'
      "
      >{{ caption }}</span
    >
  </div>
</template>
