<script setup lang="ts">
import { computed } from "vue";
import { ApCallout, formatAbsolute } from "@/ui";
import type { Superseded } from "./api.ts";

/** Why this draft is no longer current (ux: superseded state): what changed, when, by whom. */
const props = defineProps<{ superseded: Superseded }>();
const REASONS: Readonly<Record<string, string>> = {
  template_changed: "A contact rule template changed",
  requirement_changed: "A contact rule changed",
  requirement_closed: "A contact rule was closed",
};
const sentence = computed(() => {
  const s = props.superseded;
  const who = s.by ? ` by ${s.by.name}` : "";
  return `${REASONS[s.reason] ?? "The contact rules changed"}${who} at ${formatAbsolute(new Date(s.at))}, so this draft no longer matches the current rules. Nothing was submitted.`;
});
const changes = computed(() =>
  props.superseded.changes.map((c) => {
    const what = `${c.kind === "template" ? "Template" : "Rule"} ${c.name ?? c.id}`;
    const versions =
      c.from_version !== null && c.to_version !== null
        ? ` v${c.from_version} → v${c.to_version}`
        : "";
    return `${what}${versions}`;
  }),
);
</script>

<template>
  <ApCallout tone="stale">
    <span class="flex flex-col gap-1">
      <span>{{ sentence }}</span>
      <span v-for="line in changes" :key="line" class="font-mono text-sm text-text-2">{{
        line
      }}</span>
    </span>
  </ApCallout>
</template>
