<script setup lang="ts">
import { ref, useId } from "vue";
import { useDisclosure } from "@/shell/index.ts";
import { ApButton } from "@/ui";
import { stateFilters, type StateFilter } from "./history.ts";

/**
 * U78 State: a multi-select of the console's contact-state words (the Event type filter's
 * pattern). The chosen words go in the URL as `?state=` keys; the read gets their `states=`.
 */
const props = defineProps<{ chosen: readonly StateFilter[] }>();
const emit = defineEmits<{ state: [keys: string | undefined] }>();
const root = ref<HTMLElement | null>(null);
const { open, toggle } = useDisclosure(root);
const listId = useId();
const has = (f: StateFilter) => props.chosen.some((c) => c.key === f.key);
function flip(f: StateFilter) {
  const next = stateFilters.filter((s) => (s.key === f.key ? !has(s) : has(s)));
  emit("state", next.length ? next.map((s) => s.key).join(",") : undefined);
}
</script>

<template>
  <div ref="root" class="relative">
    <ApButton
      size="compact"
      variant="secondary"
      :aria-expanded="open ? 'true' : 'false'"
      :aria-controls="listId"
      @click="toggle"
      >State{{ chosen.length ? ` · ${chosen.length}` : "" }}</ApButton
    >
    <fieldset
      v-if="open"
      :id="listId"
      class="absolute top-full left-0 z-30 m-0 mt-1 flex w-[260px] flex-col border border-line bg-raised p-3"
    >
      <legend class="sr-only">State</legend>
      <label
        v-for="f in stateFilters"
        :key="f.key"
        class="flex min-h-11 cursor-pointer items-center gap-2 text-md text-readout"
      >
        <input
          type="checkbox"
          class="accent-[var(--color-readout)] [color-scheme:dark]"
          :checked="has(f)"
          @change="flip(f)"
        />
        {{ f.word }}
      </label>
    </fieldset>
  </div>
</template>
