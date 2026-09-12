<script setup lang="ts">
import type { OpsPagePort, OpsPageReadPort } from "@cadence/plugin-sdk/ops-pages";
import type { PlanDetailPort } from "./OpsContactPlanShow.contracts";
import type { PlanReviewPage } from "./plan-review";
import OpsContactPlanShow from "./OpsContactPlanShow.vue";
defineOptions({ inheritAttrs: false });
const props = defineProps<{ page: PlanReviewPage; port: OpsPagePort; readPort: OpsPageReadPort }>();
const reviewPort: PlanDetailPort = {
  context: { ...props.page.detail.context, plan_id: props.page.detail.plan.id },
  captured: {
    actorId: props.page.actor_id,
    guardNavigation: (guard) => props.port.guardNavigation?.(guard) ?? (() => {}),
  },
  execute: (action, input) => props.port.execute(action, input),
  refresh: () => props.readPort.read(),
};
</script>
<template>
  <section id="plan-review-contribution" class="min-w-0">
    <OpsContactPlanShow :detail="page" :port="reviewPort" />
  </section>
</template>
