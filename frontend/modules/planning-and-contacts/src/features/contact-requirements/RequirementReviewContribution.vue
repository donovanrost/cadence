<script setup lang="ts">
import type { OpsPagePort, OpsPageReadPort } from "@cadence/plugin-sdk/ops-pages";
import type { RequirementPage } from "./requirement-workflow";
import { useRequirementWorkflow } from "./use-requirement-workflow";
import OpsContactRequirementShow from "./OpsContactRequirementShow.vue";
defineOptions({ inheritAttrs: false });
const props = defineProps<{
  page: RequirementPage;
  port: OpsPagePort;
  readPort: OpsPageReadPort;
}>();
const {
  detail,
  operation,
  pending,
  uncertain,
  disabled,
  notice,
  result,
  nextHref,
  refresh,
  submit,
} = useRequirementWorkflow(
  () => props.page,
  () => props.port,
  () => props.readPort,
);
</script>
<template>
  <section id="requirement-review-contribution" class="min-w-0 space-y-4">
    <div class="flex flex-wrap items-center justify-between gap-3 px-4 pt-4">
      <p id="requirement-review-notice" role="status" class="text-sm text-base-content/65">
        {{ notice }}
      </p>
      <button
        id="requirement-review-refresh"
        class="btn btn-ghost btn-sm"
        :disabled="pending"
        @click="refresh"
      >
        Refresh requirement evidence
      </button>
    </div>
    <p
      v-if="uncertain"
      id="requirement-review-unconfirmed"
      role="alert"
      class="mx-4 border border-warning/40 p-3 text-sm"
    >
      Further actions are paused. Refresh to recover the receipt before another planning decision.
    </p>
    <div
      v-if="operation?.status === 'completed'"
      id="requirement-review-receipt"
      class="mx-4 flex flex-wrap items-center gap-3 text-xs text-base-content/60"
    >
      <span>{{ operation.action }} · completed · {{ operation.receipt?.receiptId }}</span>
      <button
        v-if="nextHref"
        id="requirement-review-open-result"
        class="btn btn-primary btn-sm"
        :disabled="pending"
        @click="port.navigate(nextHref)"
      >
        {{ operation.action === "plan" ? "Review planning run" : "Open contact plan" }}
      </button>
    </div>
    <OpsContactRequirementShow
      :detail="detail"
      :workflow="{
        pending: disabled,
        busy: pending,
        result,
        guardNavigation: (guard) => port.guardNavigation?.(guard) ?? (() => {}),
      }"
      @plan="submit('plan', $event)"
      @create-plan="submit('create-plan', $event)"
    />
  </section>
</template>
