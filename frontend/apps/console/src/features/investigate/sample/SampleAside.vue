<script setup lang="ts">
import { onMounted, ref, useId } from "vue";
import type { RemoteState } from "@/api/index.ts";
import { ApSheet } from "@/ui";
import type { SampleRead } from "./api.ts";
import SampleBody from "./SampleBody.vue";

/**
 * ux U80: the Sample aside. From 1100px it takes T1's column (360px) so the plot doesn't move; the
 * heading takes focus on open, and Esc or × closes it. Below 1100px it's a side sheet.
 */
const props = defineProps<{
  state: RemoteState<SampleRead>;
  title: string;
  atLabel: string | null;
  today: string;
  wide: boolean;
  /** Where focus lands on close (T1's search): the opener is on another tab. */
  returnFocus: () => HTMLElement | null;
}>();
const emit = defineEmits<{ close: []; retry: [] }>();
const heading = ref<HTMLElement | null>(null);
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const titleId = useId();
onMounted(() => (props.wide ? heading.value?.focus() : sheet.value?.open()));
const onKey = (e: KeyboardEvent) => {
  if (e.key === "Escape") emit("close");
};
</script>

<template>
  <section
    v-if="wide"
    class="flex min-h-0 flex-col overflow-hidden border border-hairline bg-panel"
    :aria-labelledby="titleId"
    @keydown="onKey"
  >
    <header class="flex flex-none items-center gap-3 border-b border-hairline px-4 py-2.5">
      <h2
        :id="titleId"
        ref="heading"
        tabindex="-1"
        class="m-0 min-w-0 flex-1 font-display text-base font-semibold tracking-title break-words text-text-2 uppercase"
      >
        {{ title }}
      </h2>
      <!-- The kit sheet's ✕ (ApSheet), named for what it closes (ux U80). -->
      <button
        type="button"
        aria-label="Close sample"
        class="-my-2 ml-auto flex size-9 flex-none cursor-pointer items-center justify-center border-0 bg-transparent text-xl text-text-3 hover:text-readout"
        @click="$emit('close')"
      >
        <span aria-hidden="true">✕</span>
      </button>
    </header>
    <div class="min-h-0 flex-1 overflow-auto">
      <SampleBody
        :state="state"
        :at-label="atLabel"
        :today="today"
        @retry="$emit('retry')"
        @show-at="$emit('close')"
      />
    </div>
  </section>
  <ApSheet
    v-else
    ref="sheet"
    :title="title"
    placement="side"
    :return-focus="returnFocus"
    @closed="$emit('close')"
  >
    <SampleBody
      :state="state"
      :at-label="atLabel"
      :today="today"
      @retry="$emit('retry')"
      @show-at="sheet?.close()"
    />
  </ApSheet>
</template>
