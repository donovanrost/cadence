<script setup lang="ts">
import { computed } from "vue";
import { ApCallout, formatAbsolute } from "@/ui";
import { isKnown } from "@/api";
import type { Superseded } from "./api.ts";

type SupersededReason = Exclude<Superseded["reason"], Readonly<{ unrecognized: string }>>;

/** Why this draft is no longer current (ux: superseded state): what changed, when, by whom. */
const props = defineProps<{ superseded: Superseded }>();
const REASONS: Readonly<Record<SupersededReason, string>> = {
  template_changed: "A contact rule template changed",
  requirement_changed: "A contact rule changed",
  requirement_closed: "A contact rule was closed",
};
const sentence = computed(() => {
  const s = props.superseded;
  const who = s.by?.name ? ` by ${s.by.name}` : "";
  // An unknown reason still says the rules changed (the server's own word isn't a sentence).
  const why = isKnown(s.reason) ? REASONS[s.reason] : "The contact rules changed";
  return `${why}${who} at ${formatAbsolute(new Date(s.at))}, so this draft no longer matches the current rules. Nothing was submitted.`;
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
