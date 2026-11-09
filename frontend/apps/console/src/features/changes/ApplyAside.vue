<script setup lang="ts">
import { computed, ref } from "vue";
import type { RemoteState } from "@/api";
import { ApButton, ApCallout, ApField, ApPanel, ApStatTile } from "@/ui";
import { rejectionSentence, submitChangeSet, type Preview, type SubmitResult } from "./actions.ts";
import type { ChangeSet, ConfigState } from "./shapes.ts";

/** K3 Apply: why (required), holds acknowledgement, apply or request review (mission policy). */
const props = defineProps<{
  missionId: string;
  config: ConfigState;
  changeSet: ChangeSet;
  preview: RemoteState<Preview>;
}>();
const emit = defineEmits<{ result: [result: SubmitResult]; changed: [] }>();

const why = ref("");
const acknowledged = ref(false);
const busy = ref(false);
const failure = ref<string | null>(null);
const next = computed(() => props.config.head.revision + 1);
const needsReview = computed(() => props.changeSet.approval_required === true);
const verdict = computed(() =>
  props.preview.status === "ready" ? props.preview.value.verdict : null,
);

const blocked = computed((): string | null => {
  if (props.changeSet.state === "in_review")
    return `r${next.value} is in review; staging is paused.`;
  if (!props.config.permissions.has("config.apply"))
    return "You can stage changes but not apply them.";
  if (verdict.value === null) return "Waiting for checks.";
  if (verdict.value === "no_go") return "A NO-GO check blocks apply. Fix it first.";
  if (verdict.value === "hold" && !acknowledged.value) return "Acknowledge the holds first.";
  if (why.value.trim().length < 10) return "Say why (10 characters or more).";
  return null;
});

async function apply() {
  if (blocked.value !== null || busy.value) return;
  busy.value = true;
  failure.value = null;
  try {
    const result = await submitChangeSet(props.missionId, props.changeSet.id, {
      reason: why.value.trim(),
      expected_version: props.changeSet.version,
      acknowledged_holds: acknowledged.value,
    });
    if (result.ok) emit("result", result.value);
    else {
      failure.value = rejectionSentence(result.error);
      emit("changed");
    }
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <ApPanel index="K3" title="Apply">
    <div class="flex flex-col gap-4">
      <div class="grid grid-cols-2 gap-px border border-hairline bg-hairline">
        <ApStatTile label="Changes" :value="changeSet.staged_count" />
        <ApStatTile label="Authors" :value="changeSet.authors.length" />
      </div>
      <ApField v-model="why" label="Why" placeholder="Goes in the revision and the audit log" />
      <label v-if="verdict === 'hold'" class="flex items-center gap-2 text-md text-readout">
        <input
          v-model="acknowledged"
          type="checkbox"
          class="size-4 accent-[var(--color-readout)]"
        />
        I've read the holds
      </label>
      <ApCallout v-if="failure" tone="crit">{{ failure }}</ApCallout>
      <ApButton
        variant="primary"
        size="commit"
        :disabled="blocked !== null || busy"
        :disabled-reason="blocked ?? 'Applying…'"
        @click="apply"
      >
        <template v-if="busy">Applying…</template>
        <template v-else-if="needsReview">Request review</template>
        <template v-else
          >Apply as <span class="font-mono normal-case">r{{ next }}</span></template
        >
      </ApButton>
      <p v-if="blocked" class="m-0 text-sm text-text-3">{{ blocked }}</p>
      <p class="m-0 font-mono text-xs text-text-4 uppercase">
        Atomic · all or nothing ·
        <span class="normal-case">r{{ config.head.revision }}</span> kept for rollback
      </p>
    </div>
  </ApPanel>
</template>
