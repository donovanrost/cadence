<script setup lang="ts">
import ApStatusMark from "./ApStatusMark.vue";
import type { OpState } from "./status.ts";

/**
 * Queue item / finding / event row: [priority] [mark] [title + sentence + meta] [one action].
 * Put rows inside an <ul class="m-0 list-none p-0"> (or ApPanel flush); the first row has no top rule.
 * Title link goes in the `title` slot; the single action in `action`.
 */
defineProps<{
  priority?: string | undefined;
  state?: OpState | undefined;
  title?: string | undefined;
  sentence?: string | undefined;
  meta?: string | undefined;
  /** Meta in readout (it's live, e.g. IN CONTACT · LOS T−03:20). */
  metaLive?: boolean | undefined;
}>();
</script>

<template>
  <li
    class="grid grid-cols-[28px_12px_minmax(0,1fr)_auto] items-start gap-2.5 border-t border-hairline px-4 py-3 first:border-t-0"
  >
    <span
      class="pt-0.5 font-mono text-xs"
      :class="
        state === 'crit'
          ? 'text-crit-text'
          : state === 'caution'
            ? 'text-caution-text'
            : 'text-text-4'
      "
      >{{ priority }}</span
    >
    <span class="pt-1.5"><ApStatusMark v-if="state" :state="state" /></span>
    <div class="flex min-w-0 flex-col gap-[3px]">
      <span class="text-base font-semibold text-readout"
        ><slot name="title">{{ title }}</slot></span
      >
      <span v-if="sentence || $slots.sentence" class="text-md text-text-3"
        ><slot name="sentence">{{ sentence }}</slot></span
      >
      <span
        v-if="meta"
        class="font-mono text-xs uppercase"
        :class="metaLive ? 'text-readout' : 'text-text-4'"
        >{{ meta }}</span
      >
    </div>
    <div><slot name="action" /></div>
  </li>
</template>
