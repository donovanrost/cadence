<script setup lang="ts">
import { fieldId } from "../field-id.ts";
import { computed } from "vue";

/** hh:mm:ss UTC spinbuttons. ↑/↓ adjust (PageUp/PageDown ×10); the ▲▼ buttons mirror them. */
const props = defineProps<{ modelValue: number }>();
const emit = defineEmits<{ "update:modelValue": [value: number] }>();

const t = computed(() => new Date(props.modelValue));
const fields = computed(
  () =>
    [
      { key: "h", label: "Hours", value: t.value.getUTCHours(), max: 23, ms: 3_600_000 },
      { key: "m", label: "Minutes", value: t.value.getUTCMinutes(), max: 59, ms: 60_000 },
      { key: "s", label: "Seconds", value: t.value.getUTCSeconds(), max: 59, ms: 1_000 },
    ] as const,
);
const pad = (n: number) => String(n).padStart(2, "0");
const bump = (ms: number, times: number) =>
  emit("update:modelValue", props.modelValue + ms * times);

function onKey(event: KeyboardEvent, ms: number) {
  const times = { ArrowUp: 1, ArrowDown: -1, PageUp: 10, PageDown: -10 }[event.key];
  if (times === undefined) return;
  event.preventDefault();
  bump(ms, times);
}
const uid = fieldId("ap-tp-time");
</script>

<template>
  <section :aria-labelledby="uid" class="flex flex-col gap-2">
    <h3 :id="uid" class="ap-label">Time · UTC</h3>
    <div class="flex items-center gap-1.5">
      <template v-for="(field, i) in fields" :key="field.key">
        <span v-if="i > 0" aria-hidden="true" class="font-sans text-2xl text-text-4">:</span>
        <div class="flex flex-col items-center">
          <button
            type="button"
            tabindex="-1"
            :aria-label="`${field.label} up`"
            class="h-6 w-12 cursor-pointer border-0 bg-transparent text-xs text-text-4 hover:text-readout max-md:h-11"
            @click="bump(field.ms, 1)"
          >
            ▲
          </button>
          <span
            role="spinbutton"
            tabindex="0"
            :aria-label="field.label"
            :aria-valuenow="field.value"
            aria-valuemin="0"
            :aria-valuemax="field.max"
            class="flex h-[42px] w-12 items-center justify-center border border-line bg-well font-sans text-[34px] leading-none font-medium tabular"
            @keydown="onKey($event, field.ms)"
            >{{ pad(field.value) }}</span
          >
          <button
            type="button"
            tabindex="-1"
            :aria-label="`${field.label} down`"
            class="h-6 w-12 cursor-pointer border-0 bg-transparent text-xs text-text-4 hover:text-readout max-md:h-11"
            @click="bump(field.ms, -1)"
          >
            ▼
          </button>
        </div>
      </template>
    </div>
  </section>
</template>
