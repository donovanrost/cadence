<script setup lang="ts">
import { computed } from "vue";
import type { OpsPagePort, OpsPageReadPort } from "@cadence/plugin-sdk/ops-pages";
import type { PolicyAction, PolicyPage } from "./fleet-policy";
import { policyActions, policyHref } from "./fleet-policy";
import { policyPresentation } from "./policy-presentation";
import { usePolicyWorkflow } from "./policy-workflow-state";
import { useFleetBootstrap } from "./use-fleet-bootstrap";
import OpsFleetPlanningPolicy from "./OpsFleetPlanningPolicy.vue";
defineOptions({ inheritAttrs: false });
const props = defineProps<{ page: PolicyPage; port: OpsPagePort; readPort: OpsPageReadPort }>();
const page = useFleetBootstrap(() => props.page);
const {
  model,
  operation,
  pending,
  uncertain,
  disabled,
  notice,
  submit,
  refresh,
  confirmedPolicyEvidence,
  confirmedGrantEvidence,
  confirmedGrantSequence,
} = usePolicyWorkflow(
  () => page.value,
  () => props.port,
  () => props.readPort,
);
const presentation = computed(() => policyPresentation(model.value));
const listeners = Object.fromEntries(
  policyActions.map((action) => [
    action,
    (input: Record<string, any>) => {
      if (action === "revoke-grant") {
        const grant = model.value.grants.entries.find(
          (g) =>
            g.reference.grant_id === input.revocation?.automation_grant_id && g.state === "active",
        );
        if (!grant) return;
        input = { ...input, grant_evidence: { ...grant.reference } };
      }
      submit(action as PolicyAction, input);
    },
  ]),
);
</script>
<template>
  <section id="fleet-policy-contribution" class="min-w-0 space-y-4">
    <div class="flex flex-wrap items-center justify-between gap-3 px-4 pt-4">
      <p id="fleet-policy-workflow-notice" role="status" class="text-sm text-base-content/65">
        {{ notice }}
      </p>
      <button
        id="fleet-policy-refresh"
        class="btn btn-ghost btn-sm"
        :disabled="!!pending"
        @click="refresh"
      >
        Refresh policy and grants
      </button>
    </div>
    <p
      v-if="uncertain"
      id="fleet-policy-unconfirmed"
      role="alert"
      class="mx-4 border border-warning/40 p-3 text-sm"
    >
      Further changes are paused. Refresh to recover the action receipt and inspect current policy
      and grant evidence.
    </p>
    <p
      v-if="operation?.status === 'completed'"
      id="fleet-policy-operation-receipt"
      class="mx-4 text-xs text-base-content/60"
    >
      {{ operation.action }} · completed · {{ operation.receipt?.receiptId }}
    </p>
    <fieldset class="m-0 min-w-0 border-0 p-0" :disabled="disabled">
      <legend class="sr-only">Reviewed fleet policy administration</legend>
      <OpsFleetPlanningPolicy
        v-bind="presentation"
        :confirmed-policy-evidence="confirmedPolicyEvidence"
        :confirmed-grant-evidence="confirmedGrantEvidence"
        :confirmed-grant-sequence="confirmedGrantSequence"
        v-on="listeners"
      />
    </fieldset>
    <nav
      v-for="kind in ['grants', 'identities'] as const"
      :key="kind"
      :id="`fleet-policy-${kind}-pages`"
      :aria-label="kind === 'grants' ? 'Automation grant pages' : 'Service identity pages'"
      class="flex flex-wrap justify-between gap-3 border-t border-base-300 p-4 text-sm"
    >
      <span
        >{{ kind === "grants" ? "Grant ledger" : "Active identity choices" }} · page
        {{ model[kind].page }}</span
      >
      <a
        v-if="model[kind].page > 1"
        :id="`fleet-policy-${kind}-previous`"
        class="text-primary"
        :href="policyHref(model, `${kind}_page`, model[kind].page - 1)"
        >Previous</a
      >
      <a
        v-if="model[kind].more"
        :id="`fleet-policy-${kind}-next`"
        class="text-primary"
        :href="policyHref(model, `${kind}_page`, model[kind].page + 1)"
        >Next</a
      >
    </nav>
  </section>
</template>
