<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref } from "vue";
import { ApButton, ApPanel } from "@/ui";
import GrantReject from "./GrantReject.vue";
import GrantRefusal from "./GrantRefusal.vue";
import { approveLabel, decideOffer, waitingLine } from "./grant-words.ts";
import type { Grant } from "./grants.ts";
import { useGrantDecision } from "./useGrantDecision.ts";

/**
 * U105 Waiting for approval, on a proposed grant (as the policy's P5). Who may decide comes from
 * the server's viewer_can_decide and cannot_decide_because only (A6, #233's pattern): Approve is
 * disabled with its reason, muted under it and as its description; Reject stays.
 */
const props = defineProps<{ missionId: MissionId; grant: Grant; viewerId: string | null }>();
const emit = defineEmits<{ decided: [said: string] }>();
const rejectSheet = ref<InstanceType<typeof GrantReject> | null>(null);
const offer = computed(() => decideOffer(props.grant));
const d = useGrantDecision(
  () => props.missionId,
  () => props.grant,
  () => props.viewerId,
  (said) => emit("decided", said),
);
const blocked = computed(() =>
  offer.value.kind === "act" ? (d.disabled.value ?? offer.value.blocked) : null,
);
async function reject(reason: string) {
  if (await d.reject(reason)) rejectSheet.value?.close();
}
</script>

<template>
  <ApPanel v-if="offer.kind !== 'none'" index="G2" title="Waiting for approval">
    <div class="flex flex-col gap-3">
      <p class="m-0 text-md text-text-3">{{ waitingLine(grant) }}</p>
      <template v-if="offer.kind === 'act'">
        <div class="flex flex-wrap gap-2">
          <ApButton
            data-grant-approve
            :variant="blocked ? 'secondary' : 'primary'"
            :disabled="blocked !== null || d.busy.value !== null"
            :disabled-reason="blocked?.text ?? 'Approving…'"
            @click="d.approve"
            >{{ approveLabel(grant) }}</ApButton
          >
          <ApButton
            data-grant-reject
            :disabled="d.busy.value !== null"
            disabled-reason="Working…"
            @click="rejectSheet?.open()"
            >Reject…</ApButton
          >
        </div>
        <p v-if="blocked" data-grant-blocked class="m-0 text-sm text-text-3">{{ blocked.text }}</p>
        <details v-if="blocked?.code" class="text-sm">
          <summary class="ap-label cursor-pointer">Technical details</summary>
          <p class="m-0 mt-1 font-mono text-xs text-text-3">{{ blocked.code }}</p>
        </details>
        <GrantRefusal :refusal="d.failure.value" />
      </template>
    </div>
    <GrantReject
      ref="rejectSheet"
      :service="grant.service_identity.name"
      :busy="d.busy.value === 'reject'"
      :error="d.rejectError.value"
      :refusal="d.rejectFailed.value"
      @reject="reject"
    />
  </ApPanel>
</template>
