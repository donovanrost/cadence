<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed } from "vue";
import { useRoute } from "vue-router";
import { useSession } from "@/shell";
import { ApButton, plural } from "@/ui";
import { useConfigState } from "./useConfigState.ts";

/** Staged bar under every Setup page (Changes.md §2). Hidden when nothing is staged. */
const props = defineProps<{ missionId: MissionId }>();
const { state } = useConfigState(props.missionId);
const session = useSession();
const route = useRoute();

// The review page is where the bar leads; showing it there would only link to itself.
const set = computed(() =>
  route.name !== "setup.changes" &&
  state.value.status === "ready" &&
  (state.value.value.change_set?.staged_count ?? 0) > 0
    ? { config: state.value.value, set: state.value.value.change_set }
    : null,
);
const next = computed(() => (set.value ? set.value.config.head.revision + 1 : 0));
const summary = computed(() => {
  const changes = set.value?.set?.changes ?? [];
  const shown = changes
    .slice(0, 2)
    .map((c) => c.summary)
    .join(", ");
  return changes.length > 2 ? `${shown} + ${changes.length - 2} more` : shown;
});
const authors = computed(() => {
  const list = set.value?.set?.authors ?? [];
  if (list.every((a) => a.id === session.user.id)) return null;
  return list.map((a) => (a.id === session.user.id ? "you" : a.name)).join(", ");
});
</script>

<template>
  <div
    v-if="set && set.set"
    class="flex flex-none flex-wrap items-center gap-x-4 gap-y-2 border-t border-line bg-raised px-6 py-3"
    role="region"
    aria-label="Staged changes"
  >
    <span class="font-mono text-sm text-text-3 uppercase">
      <template v-if="set.set.state === 'in_review'"
        ><span class="normal-case">r{{ next }}</span> in review</template
      >
      <template v-else>Staged · not applied</template>
    </span>
    <span class="min-w-0 flex-1 text-base text-readout">
      <b>{{ plural(set.set.staged_count, "change") }}:</b> {{ summary }}
      <span v-if="authors" class="text-text-3"> by {{ authors }}</span>
      <span v-if="set.set.state === 'in_review'" class="text-text-3"> · staging is paused</span>
    </span>
    <ApButton variant="primary" :to="{ name: 'setup.changes' }">
      <template v-if="set.set.state === 'in_review'">Open review</template>
      <template v-else
        >Review &amp; apply as <span class="font-mono normal-case">r{{ next }}</span></template
      >
    </ApButton>
  </div>
</template>
