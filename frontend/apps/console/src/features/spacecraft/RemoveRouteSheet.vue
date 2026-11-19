<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { ref } from "vue";
import { useRouter } from "vue-router";
import {
  failureOutcome,
  refreshConfigState,
  stageChange,
  type FailureOutcome,
} from "@/features/changes/index.ts";
import { ApButton, ApCallout, ApSheet } from "@/ui";
import { removeRouteOp, routeChangeSummary } from "./routes.ts";

/** U79 Remove… on a "This spacecraft only" route: staged like any change (`delete`). */
const props = defineProps<{ missionId: MissionId; spacecraftName: string }>();
const router = useRouter();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const target = ref<Readonly<{ routeId: string; name: string; station: string }> | null>(null);
const failure = ref<string | null>(null);
/** #413: a refusal's way out (U79 conversion_in_progress: Open change set), beside its words. */
const failureLink = ref<FailureOutcome["link"] | null>(null);
const busy = ref(false);

function open(route: Readonly<{ routeId: string; name: string; station: string }>) {
  target.value = route;
  failure.value = null;
  failureLink.value = null;
  sheet.value?.open();
}
async function stage() {
  const route = target.value;
  if (!route || busy.value) return;
  busy.value = true;
  try {
    const r = await stageChange(props.missionId, {
      summary: routeChangeSummary("Remove", route.name, route.station, props.spacecraftName),
      source: { surface: "spacecraft" },
      ops: [removeRouteOp(route.routeId)],
    });
    if (!r.ok) {
      const outcome = failureOutcome(r.error, "staged");
      failure.value = outcome.sentence;
      failureLink.value = outcome.link ?? null;
      return;
    }
    refreshConfigState(props.missionId);
    await router.push({ name: "setup.changes" });
  } finally {
    busy.value = false;
  }
}
defineExpose({ open });
</script>

<template>
  <ApSheet ref="sheet" :title="`Remove ${target?.name ?? 'extra route'}?`">
    <p class="m-0 text-md text-text-2">
      {{ spacecraftName }} stops using this route when the change set is applied. Booked and running
      contacts keep the routes they were booked with.
    </p>
    <ApCallout v-if="failure" tone="crit"
      >{{ failure }}
      <template v-if="failureLink" #action>
        <ApButton size="compact" :to="failureLink.to">{{ failureLink.label }}</ApButton>
      </template>
    </ApCallout>
    <template #footer>
      <ApButton variant="ghost" @click="sheet?.close()">Cancel</ApButton>
      <ApButton variant="danger" :disabled="busy" disabled-reason="Staging…" @click="stage"
        >Stage removal</ApButton
      >
    </template>
  </ApSheet>
</template>
