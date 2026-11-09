<script setup lang="ts">
import { computed } from "vue";
import { useRoute, useRouter } from "vue-router";
import { ApButton, ApTimePicker } from "@/ui";
import { dayLabel } from "./names.ts";

/** ‹ TUE 10 NOV › + a day pick, synced to `?day=` (UTC days, U22 Q1). */
const props = defineProps<{ day: string }>();
const route = useRoute();
const router = useRouter();
const DAY = 86_400_000;
const at = computed(() => Date.parse(`${props.day}T00:00:00Z`));
const iso = (t: number) => new Date(t).toISOString().slice(0, 10);

function go(t: number | null) {
  if (t === null) return;
  void router
    .replace({ query: { ...route.query, day: iso(t), run: undefined } })
    .catch(() => undefined);
}
</script>

<template>
  <div class="flex flex-none flex-wrap items-end gap-2">
    <ApButton
      size="standard"
      :aria-label="`Previous day, ${dayLabel(iso(at - DAY))}`"
      @click="go(at - DAY)"
      >‹</ApButton
    >
    <div class="w-[230px]">
      <ApTimePicker :model-value="at" label="Plan day" date-only @update:model-value="go" />
    </div>
    <ApButton
      size="standard"
      :aria-label="`Next day, ${dayLabel(iso(at + DAY))}`"
      @click="go(at + DAY)"
      >›</ApButton
    >
  </div>
</template>
