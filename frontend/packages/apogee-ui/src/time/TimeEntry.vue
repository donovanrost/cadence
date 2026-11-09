<script setup lang="ts">
import { fieldId } from "../field-id.ts";
import { computed, ref } from "vue";
import { parseTime } from "./parse.ts";

/** Type-a-time input with live parse status. Emits only times it could read. */
const props = defineProps<{ now: number; metAvailable: boolean }>();
const emit = defineEmits<{ parsed: [at: number] }>();

const text = ref("");
const status = computed<"idle" | "ok" | "bad">(() => {
  if (text.value.trim() === "") return "idle";
  return parseTime(text.value, props.now) === null ? "bad" : "ok";
});
function onInput(event: Event) {
  if (!(event.target instanceof HTMLInputElement)) return;
  text.value = event.target.value;
  const at = parseTime(text.value, props.now);
  if (at !== null) emit("parsed", at);
}
const uid = fieldId("ap-tp-entry");
</script>

<template>
  <div class="flex flex-wrap items-end gap-4">
    <div class="flex min-w-[260px] flex-1 flex-col gap-1.5">
      <label :for="uid" class="ap-label">Type a time</label>
      <input
        :id="uid"
        :value="text"
        type="text"
        autocomplete="off"
        spellcheck="false"
        placeholder="now+2h · T+38m · 2026-10-24 06:00"
        :aria-describedby="uid + '-status'"
        :aria-invalid="status === 'bad' ? 'true' : undefined"
        class="h-[38px] border bg-well px-3 font-mono text-base text-readout outline-none placeholder:text-text-4 focus:border-readout"
        :class="status === 'bad' ? 'border-caution' : 'border-line'"
        @input="onInput"
      />
    </div>
    <p
      :id="uid + '-status'"
      role="status"
      class="m-0 pb-2.5 font-mono text-xs uppercase"
      :class="status === 'bad' ? 'text-caution-text' : 'text-text-4'"
    >
      {{ status === "ok" ? "Parsed" : status === "bad" ? "Can’t read that" : "Type or pick" }}
    </p>
    <p class="m-0 pb-2.5 font-mono text-xs text-text-4 uppercase">
      All times UTC<span v-if="metAvailable"> · MET shown below</span>
    </p>
  </div>
</template>
