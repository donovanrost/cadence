<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import { ApEmptyState, ApPageHeader, ApPanel } from "@/ui";
import { useConsoleScope } from "./scope.ts";

/** Honest placeholder for routes whose screen isn't built yet. */
const route = useRoute();
const scope = useConsoleScope();
const label = computed(() => {
  const s = scope.value;
  if (s.kind === "mission")
    return `${s.mission.name} · ${route.meta.mode === "setup" ? "setup" : "ops"}`;
  if (s.kind === "organization") return s.organization.name;
  return "Cadence";
});
</script>

<template>
  <div class="flex flex-col gap-3">
    <ApPageHeader :label="label" :title="route.meta.title ?? 'Screen'" />
    <ApPanel index="A1" title="Not built yet" flush>
      <ApEmptyState
        state="off"
        headline="This screen is on the way"
        :sentence="
          route.meta.board
            ? `It will implement the ${route.meta.board} board. Until then, use the existing Cadence pages.`
            : 'Until it ships, use the existing Cadence pages.'
        "
      />
    </ApPanel>
  </div>
</template>
