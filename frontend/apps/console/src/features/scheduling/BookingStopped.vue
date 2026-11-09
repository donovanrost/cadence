<script setup lang="ts">
import { computed } from "vue";
import { useRemoteQuery } from "@/api";
import { fetchPasses } from "@/features/contacts/index.ts";
import { useMissionInvalidation } from "@/live";
import { ApCallout } from "@/ui";
import type { PlanDetail } from "./api.ts";
import { bookingStoppedText, bookingWindow } from "./booking.ts";

/** U20: K1's interrupted execution. How many requests went out, from the passes read. */
const props = defineProps<{ missionId: string; plan: PlanDetail }>();
// A string key, so a refetched plan (a new object) doesn't reload the passes read.
const key = computed(() => {
  const w = bookingWindow(props.plan);
  return w ? `${props.missionId}|${w.from}|${w.to}` : null;
});
const passes = useRemoteQuery(key, (k, signal) => {
  const [mission = "", from = "", to = ""] = k.split("|");
  return fetchPasses(mission, { from: new Date(from), to: new Date(to) }, signal);
});
useMissionInvalidation(
  computed(() => props.missionId),
  ["contacts"],
  passes.refetch,
);
const text = computed(() =>
  bookingStoppedText(
    props.plan,
    passes.state.value.status === "ready" ? passes.state.value.value : null,
  ),
);
</script>

<template>
  <ApCallout tone="stale">{{ text }}</ApCallout>
</template>
