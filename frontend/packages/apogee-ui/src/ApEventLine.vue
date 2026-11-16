<script setup lang="ts">
import ApStatusMark from "./ApStatusMark.vue";
import type { OpState } from "./status.ts";

/**
 * One event: time | mark | text. Use inside <ol class="m-0 list-none p-0">, newest first.
 * `selected` (true or false) makes the row selectable (Timeline's event detail, ux U71): the time
 * becomes a toggle button (aria-pressed) that emits `select`, and a selected row has the white left
 * bar. Leave it unset for a plain row.
 */
// `selected` defaults to undefined, not Vue's boolean-cast false: unset means a plain row.
withDefaults(
  defineProps<{
    time: string;
    datetime?: string | undefined;
    state: OpState;
    /** Log rows (uplink event stream): mono 12 text. */
    mono?: boolean | undefined;
    selected?: boolean | undefined;
  }>(),
  { selected: undefined },
);
const emit = defineEmits<{ select: [] }>();
</script>

<template>
  <li
    class="grid grid-cols-[88px_14px_minmax(0,1fr)] items-baseline gap-2.5 px-4 py-1.5"
    :class="selected ? 'bg-raised shadow-[inset_2px_0_0_var(--color-readout)]' : ''"
  >
    <button
      v-if="selected !== undefined"
      type="button"
      :aria-pressed="selected ? 'true' : 'false'"
      class="max-md:hit-44 cursor-pointer border-0 bg-transparent p-0 text-left font-mono text-sm text-text-4 hover:text-readout hover:underline"
      :class="selected ? 'text-readout' : ''"
      @click="emit('select')"
    >
      <time :datetime="datetime">{{ time }}</time>
    </button>
    <time v-else class="font-mono text-sm text-text-4" :datetime="datetime">{{ time }}</time>
    <span class="self-center"><ApStatusMark :state="state" /></span>
    <span :class="mono ? 'font-mono text-sm text-text-2' : 'text-base text-text-2'"><slot /></span>
  </li>
</template>
