<script setup lang="ts">
import { computed, ref } from "vue";
import { useRouter } from "vue-router";
import { useRemoteQuery, type MissionId } from "@/api/index.ts";
import { ApButton, ApCallout } from "@/ui";
import {
  CALLOUT,
  NOT_ADMIN,
  NOTHING_LEFT,
  fetchConversion,
  progressLine,
  skippedLine,
  skippedSpacecraft,
  stageFailure,
  stageLabel,
  stagedLine,
  stageNextBatch,
  type SkippedRoute,
  type StageFailure,
} from "./legacy-conversion.ts";

/**
 * TEMPORARY, deleted with 9ac6dc8ee. ux U79: on a spacecraft's routing page with routes from the old
 * routing page, stage the mission's next conversion batch. No skipped routes: open the change set;
 * some skipped: stay and say which (ux).
 */
const props = defineProps<{ missionId: MissionId }>();
const router = useRouter();
const { state, refetch } = useRemoteQuery(() => props.missionId, fetchConversion);
const conversion = computed(() => (state.value.status === "ready" ? state.value.value : null));
const busy = ref(false);
const failure = ref<StageFailure | null>(null);
const staged = ref<Readonly<{ batch: number; skipped: readonly SkippedRoute[] }> | null>(null);
const OPEN_SET = { name: "setup.changes" } as const;
const pending = computed(() => conversion.value?.staged_batch ?? null);
const label = computed(() =>
  conversion.value?.can_stage && !pending.value && !staged.value && !failure.value?.retry
    ? stageLabel(conversion.value)
    : null,
);
const showOpen = computed(
  () => staged.value !== null || pending.value !== null || failure.value?.openSet === true,
);

async function stage() {
  if (busy.value) return;
  busy.value = true;
  failure.value = null;
  try {
    const result = await stageNextBatch(props.missionId);
    if (!result.ok) failure.value = stageFailure(result.error);
    else if (result.value.unmappable.length === 0) return void (await router.push(OPEN_SET));
    else staged.value = { batch: result.value.batch, skipped: result.value.unmappable };
    refetch();
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <ApCallout v-if="conversion" tone="info">
    <p class="m-0">{{ CALLOUT }} {{ progressLine(conversion) }}</p>
    <template v-if="staged">
      <p class="m-0 mt-2">Batch {{ staged.batch }} is staged. {{ skippedLine(staged.skipped) }}</p>
      <ul class="m-0 mt-1 ps-5">
        <li v-for="sc in skippedSpacecraft(staged.skipped)" :key="sc.id">
          <RouterLink
            :to="{ name: 'setup.spacecraft.one', params: { spacecraftId: sc.id } }"
            class="text-primary no-underline hover:underline"
            >{{ sc.name ?? "Unknown spacecraft" }}</RouterLink
          >
        </li>
      </ul>
    </template>
    <p v-else-if="pending" class="m-0 mt-2">
      {{ stagedLine(pending.batch, pending.author.name) }}
    </p>
    <p v-else-if="!conversion.can_stage" class="m-0 mt-2 text-text-3">{{ NOT_ADMIN }}</p>
    <p v-else-if="conversion.next_batch === null" class="m-0 mt-2">{{ NOTHING_LEFT }}</p>
    <p v-if="failure" class="m-0 mt-2" role="alert">{{ failure.sentence }}</p>
    <template #action>
      <ApButton v-if="label" :disabled="busy" disabled-reason="Staging…" @click="stage">{{
        busy ? "Staging…" : label
      }}</ApButton>
      <ApButton v-if="failure?.retry" size="compact" @click="stage">Try again</ApButton>
      <ApButton v-if="showOpen" size="compact" :to="OPEN_SET">Open change set</ApButton>
    </template>
  </ApCallout>
</template>
