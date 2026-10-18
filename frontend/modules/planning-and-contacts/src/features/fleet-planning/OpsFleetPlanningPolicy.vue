<script setup lang="ts">
import type {
  PolicyForm,
  GrantForm,
  PolicyValues,
  GrantValues,
  PolicyFields,
  GrantFields,
  OpsFleetPlanningPolicyProps,
  OpsFleetPlanningPolicyEmits,
} from "./OpsFleetPlanningPolicy.contracts";
import { useOpsHeader } from "@cadence/plugin-sdk/page-header";
import CadenceCollapsible from "@cadence/ui/CadenceCollapsible.vue";
import CadenceCollapsibleContent from "@cadence/ui/CadenceCollapsibleContent.vue";
import CadenceCollapsibleTrigger from "@cadence/ui/CadenceCollapsibleTrigger.vue";
import CadenceField from "@cadence/ui/CadenceField.vue";
import CadenceDetailsFrame from "@cadence/ui/CadenceDetailsFrame.vue";
import CadenceInlineWarning from "@cadence/ui/CadenceInlineWarning.vue";
import CadenceValidationMessage from "@cadence/ui/CadenceValidationMessage.vue";
import { computed, reactive, ref, watch } from "vue";
import {
  admitPolicyEvidence,
  policyEvidenceKey,
  admitPolicyEditReference,
  policyEditReferenceKey,
  type PolicyEditReference,
  type PolicyEvidence,
} from "./policy-evidence";
import CadencePanel from "@cadence/ui/CadencePanel.vue";

const props = defineProps<OpsFleetPlanningPolicyProps>();

const emit = defineEmits<OpsFleetPlanningPolicyEmits>();
useOpsHeader("/missions/:mission_id/ops/planning/policy", () => ({
  description: props.page.header.copy,
  facts: [props.page.state.label],
}));

const searchPolicyFieldKeys = [
  "max_horizon_duration",
  "requirement_concurrency",
  "provider_search_concurrency",
  "reuse_freshness_seconds",
] as const;

const automationPolicyFieldKeys = [
  "execution_concurrency",
  "max_repair_attempts",
  "repair_horizon_duration",
] as const;

const redundancyPolicyFieldKeys = [
  "distinct_provider_required",
  "distinct_station_required",
  "distinct_service_pool_required",
] as const;

const emptyPolicyValues = (): PolicyValues => ({
  max_horizon_duration: "",
  requirement_concurrency: "",
  provider_search_concurrency: "",
  reuse_freshness_seconds: "",
  max_contacts: "",
  max_estimated_cost_micros: "",
  currency: "",
  critical_contact_reserve: "",
  automation_mode: "advisory",
  execution_concurrency: "",
  max_repair_attempts: "",
  repair_horizon_duration: "",
  automatic_submission: false,
  distinct_provider_required: false,
  distinct_station_required: false,
  distinct_service_pool_required: false,
});

const policyValuesFromForm = (form: PolicyForm | null): PolicyValues => {
  if (!form) return emptyPolicyValues();

  return {
    max_horizon_duration: form.fields.max_horizon_duration.value,
    requirement_concurrency: form.fields.requirement_concurrency.value,
    provider_search_concurrency: form.fields.provider_search_concurrency.value,
    reuse_freshness_seconds: form.fields.reuse_freshness_seconds.value,
    max_contacts: form.fields.max_contacts.value,
    max_estimated_cost_micros: form.fields.max_estimated_cost_micros.value,
    currency: form.fields.currency.value,
    critical_contact_reserve: form.fields.critical_contact_reserve.value,
    automation_mode: form.fields.automation_mode.value,
    execution_concurrency: form.fields.execution_concurrency.value,
    max_repair_attempts: form.fields.max_repair_attempts.value,
    repair_horizon_duration: form.fields.repair_horizon_duration.value,
    automatic_submission: form.fields.automatic_submission.value,
    distinct_provider_required: form.fields.distinct_provider_required.value,
    distinct_station_required: form.fields.distinct_station_required.value,
    distinct_service_pool_required: form.fields.distinct_service_pool_required.value,
  };
};

const stringValue = (value: string | number) => String(value ?? "");
const checkboxValue = (value: boolean) => (value ? "true" : "false");

const normalizedPolicy = (values: PolicyValues): PolicyFields => {
  const normalized: PolicyFields = {
    max_horizon_duration: stringValue(values.max_horizon_duration),
    requirement_concurrency: stringValue(values.requirement_concurrency),
    provider_search_concurrency: stringValue(values.provider_search_concurrency),
    reuse_freshness_seconds: stringValue(values.reuse_freshness_seconds),
    max_contacts: stringValue(values.max_contacts),
    max_estimated_cost_micros: stringValue(values.max_estimated_cost_micros),
    currency: values.currency,
    critical_contact_reserve: stringValue(values.critical_contact_reserve),
    automation_mode: values.automation_mode,
    execution_concurrency: stringValue(values.execution_concurrency),
    max_repair_attempts: stringValue(values.max_repair_attempts),
    repair_horizon_duration: stringValue(values.repair_horizon_duration),
    automatic_submission: checkboxValue(
      values.automation_mode !== "advisory" && values.automatic_submission,
    ),
    distinct_provider_required: checkboxValue(values.distinct_provider_required),
    distinct_station_required: checkboxValue(values.distinct_station_required),
    distinct_service_pool_required: checkboxValue(values.distinct_service_pool_required),
  };

  return normalized;
};

const policy = reactive<PolicyValues>(policyValuesFromForm(props.policy_form));
const currentPolicyEvidence = computed(() => admitPolicyEvidence(props.page.policy_evidence));
const currentEditReference = computed(() => {
  const reference = admitPolicyEditReference(props.policy_form?.edit_reference);
  if (!reference) return null;
  if (reference.base === null) return props.page.policy_evidence === null ? reference : null;
  return policyEvidenceKey(reference.base) === policyEvidenceKey(currentPolicyEvidence.value)
    ? reference
    : null;
});
const editingReference = ref<PolicyEditReference | null>(currentEditReference.value);
const initialPolicy = ref(JSON.stringify(normalizedPolicy(policy)));
const policyDirty = computed(
  () => JSON.stringify(normalizedPolicy(policy)) !== initialPolicy.value,
);
const policyStale = computed(
  () =>
    !!editingReference.value &&
    policyEditReferenceKey(editingReference.value) !==
      policyEditReferenceKey(currentEditReference.value),
);
const canSavePolicy = computed(
  () =>
    !!props.policy_form &&
    !!editingReference.value &&
    !!currentEditReference.value &&
    !policyStale.value,
);

const loadCurrentPolicy = () => {
  Object.assign(policy, policyValuesFromForm(props.policy_form));
  editingReference.value = currentEditReference.value;
  initialPolicy.value = JSON.stringify(normalizedPolicy(policy));
};

watch(
  () => JSON.stringify(props.policy_form),
  () => {
    if (!props.policy_form || !policyDirty.value) loadCurrentPolicy();
  },
);

let acceptedPolicyReceipt = "";
watch(
  () => [props.confirmedPolicyEvidence, currentEditReference.value] as const,
  ([confirmed, reference]) => {
    const key = policyEvidenceKey(admitPolicyEvidence(confirmed));
    if (
      key &&
      key !== acceptedPolicyReceipt &&
      key === policyEvidenceKey(reference?.base ?? null)
    ) {
      loadCurrentPolicy();
      acceptedPolicyReceipt = key;
    }
  },
);

const validatePolicy = () => {
  const reference = editingReference.value;
  if (!canSavePolicy.value || !reference) return;
  emit("validate-policy", {
    policy: normalizedPolicy(policy),
    edit_reference: reference,
  });
};

const savePolicy = () => {
  const reference = editingReference.value;
  if (!canSavePolicy.value || !reference) return;
  emit("save-policy", {
    policy: normalizedPolicy(policy),
    edit_reference: reference,
  });
};

const approvalReason = ref(props.approval_form?.reason.value ?? "");
const approvalEvidence = computed(() => {
  const evidence = admitPolicyEvidence(props.approval_form?.policy_evidence);
  return evidence && policyEvidenceKey(evidence) === policyEvidenceKey(currentPolicyEvidence.value)
    ? evidence
    : null;
});
const grantEvidence = computed(() => {
  const evidence = admitPolicyEvidence(props.grant_form?.policy_evidence);
  const current = currentPolicyEvidence.value;
  return evidence &&
    current &&
    evidence.organization_id === current.organization_id &&
    evidence.mission_id === current.mission_id &&
    evidence.policy_id === current.policy_id
    ? evidence
    : null;
});

watch(
  [() => policyEvidenceKey(approvalEvidence.value), () => props.approval_form?.reason.value ?? ""],
  ([, reason]) => {
    approvalReason.value = reason;
  },
);

const approvePolicy = () => {
  const evidence = approvalEvidence.value;
  if (!evidence) return;
  emit("approve-policy", {
    decision: { reason: approvalReason.value, policy_evidence: evidence },
  });
};

const emptyGrantValues = (): GrantValues => ({
  service_identity_id: "",
  maximum_horizon_duration: "",
  maximum_contacts: "",
  maximum_execution_concurrency: "",
  valid_days: "",
  approval_reason: "",
});

const grantValuesFromForm = (form: GrantForm | null): GrantValues => {
  if (!form) return emptyGrantValues();

  return {
    service_identity_id: form.fields.service_identity_id.value,
    maximum_horizon_duration: form.fields.maximum_horizon_duration.value,
    maximum_contacts: form.fields.maximum_contacts.value,
    maximum_execution_concurrency: form.fields.maximum_execution_concurrency.value,
    valid_days: form.fields.valid_days.value,
    approval_reason: form.fields.approval_reason.value,
  };
};

const normalizedGrant = (values: GrantValues): GrantFields => ({
  service_identity_id: values.service_identity_id,
  maximum_horizon_duration: stringValue(values.maximum_horizon_duration),
  maximum_contacts: stringValue(values.maximum_contacts),
  maximum_execution_concurrency: stringValue(values.maximum_execution_concurrency),
  valid_days: stringValue(values.valid_days),
  approval_reason: values.approval_reason,
});

const grant = reactive<GrantValues>(grantValuesFromForm(props.grant_form));

const grantInitial = ref(JSON.stringify(normalizedGrant(grant)));
const editingGrantEvidence = ref<PolicyEvidence | null>(grantEvidence.value);
const grantDirty = computed(() => JSON.stringify(normalizedGrant(grant)) !== grantInitial.value);
const grantStale = computed(
  () => policyEvidenceKey(editingGrantEvidence.value) !== policyEvidenceKey(grantEvidence.value),
);
const loadCurrentGrant = () => {
  Object.assign(grant, grantValuesFromForm(props.grant_form));
  grantInitial.value = JSON.stringify(normalizedGrant(grant));
  editingGrantEvidence.value = grantEvidence.value;
};
watch(
  () => props.grant_form,
  () => {
    if (!grantDirty.value) loadCurrentGrant();
  },
  { deep: true },
);
let acceptedGrantReceipt = 0;
watch(
  () => [props.confirmedGrantSequence, props.confirmedGrantEvidence, props.grant_form] as const,
  ([sequence, evidence]) => {
    if (
      sequence &&
      sequence !== acceptedGrantReceipt &&
      policyEvidenceKey(admitPolicyEvidence(evidence)) === policyEvidenceKey(grantEvidence.value)
    ) {
      loadCurrentGrant();
      acceptedGrantReceipt = sequence;
    }
  },
);

const validateGrant = () => {
  emit("validate-grant", { grant: normalizedGrant(grant) });
  return Object.values(normalizedGrant(grant)).every((value) => value !== "");
};

const issueGrant = () => {
  const evidence = editingGrantEvidence.value;
  if (!evidence || grantStale.value) return;
  emit("issue-grant", { grant: normalizedGrant(grant), policy_evidence: evidence });
};

const revocation = reactive({ automation_grant_id: "", reason: "" });
const revocationInitial = ref(JSON.stringify(revocation));

watch(
  () => props.revocation_form,
  (serverForm) => {
    if (!serverForm) {
      Object.assign(revocation, { automation_grant_id: "", reason: "" });
      return;
    }

    if (
      JSON.stringify(revocation) !== revocationInitial.value &&
      serverForm.fields.automation_grant_id.options.some(
        (option) => option.value === revocation.automation_grant_id,
      )
    )
      return;
    Object.assign(revocation, {
      automation_grant_id:
        serverForm.fields.automation_grant_id.value ||
        serverForm.fields.automation_grant_id.options[0]?.value ||
        "",
      reason: serverForm.fields.reason.value,
    });
    revocationInitial.value = JSON.stringify(revocation);
  },
  { deep: true, immediate: true },
);

const revokeGrant = () => {
  emit("revoke-grant", {
    revocation: {
      automation_grant_id: revocation.automation_grant_id,
      reason: revocation.reason,
    },
  });
};
</script>

<template>
  <section id="ops-fleet-planning-policy-page" class="h-full overflow-y-auto bg-base-100">
    <div class="grid gap-5 xl:grid-cols-[minmax(0,1.25fr)_minmax(24rem,0.75fr)]">
      <div class="min-w-0 space-y-5">
        <CadencePanel
          :id="page.manifest.id"
          class="border border-base-300 bg-base-200/15"
          header-class="flex flex-wrap items-center justify-between gap-3 border-b border-base-300 px-4 py-3"
        >
          <template #header>
            <div>
              <p class="hud-label">Current immutable version</p>
              <p class="mt-1 font-mono text-sm">{{ page.manifest.version_label }}</p>
            </div>
            <p
              v-if="page.manifest.content_sha256"
              class="max-w-md break-all text-right font-mono text-[0.58rem] text-base-content/40"
            >
              {{ page.manifest.content_sha256 }}
            </p>
          </template>

          <div v-if="page.manifest.sections.length > 0" class="grid md:grid-cols-2">
            <div
              v-for="section in page.manifest.sections"
              :key="section.title"
              class="border-b border-base-300 p-4 last:border-b-0 md:border-r md:odd:border-r md:even:border-r-0"
            >
              <p class="hud-label">{{ section.title }}</p>
              <dl class="mt-3 space-y-2 text-xs">
                <div
                  v-for="fact in section.facts"
                  :key="fact.term"
                  class="flex items-center justify-between gap-4"
                >
                  <dt class="text-base-content/50">{{ fact.term }}</dt>
                  <dd class="font-mono text-right text-base-content/75">{{ fact.value }}</dd>
                </div>
              </dl>
            </div>
          </div>

          <div
            v-else-if="page.manifest.empty"
            :id="page.manifest.empty.id"
            class="px-6 py-14 text-center"
          >
            <span :class="[page.manifest.empty.icon, 'mx-auto h-8 w-8 text-warning/50']"></span>
            <h2 class="mt-4 text-base font-semibold">{{ page.manifest.empty.title }}</h2>
            <p class="mx-auto mt-2 max-w-xl text-sm text-base-content/55">
              {{ page.manifest.empty.copy }}
            </p>
          </div>
        </CadencePanel>

        <section
          v-if="policy_form"
          :id="policy_form.panel_id"
          class="border border-base-300 bg-base-200/15"
        >
          <CadenceCollapsible
            :content-id="policy_form.id"
            :open="policy_form.open"
            client-seeded
            :seed-epoch="`${policy_form.id}:${policy_form.open}`"
            :unmount-on-hide="false"
          >
            <div>
              <CadenceCollapsibleTrigger>
                <button type="button" class="cursor-pointer px-4 py-3 text-sm font-semibold">
                  {{ policy_form.summary }}
                </button>
              </CadenceCollapsibleTrigger>
              <CadenceCollapsibleContent>
                <form
                  :id="policy_form.id"
                  class="space-y-5 border-t border-base-300 p-4"
                  @submit.prevent="savePolicy"
                >
                  <CadenceInlineWarning v-if="!canSavePolicy" id="fleet-policy-edit-unavailable">
                    <span v-if="policyStale" class="block">
                      The policy changed while you were editing. Your inputs are retained, but this
                      draft cannot be saved against a different version.
                    </span>
                    <span v-else class="block">
                      The policy editing reference is unavailable. Refresh before making changes.
                    </span>
                    <button
                      v-if="policyStale && currentEditReference"
                      id="fleet-policy-load-current"
                      type="button"
                      class="btn btn-sm mt-2 h-auto max-w-full whitespace-normal py-2 text-left"
                      @click="loadCurrentPolicy"
                    >
                      Load current policy and discard edits
                    </button>
                  </CadenceInlineWarning>
                  <p id="fleet-policy-duration-help" class="text-xs text-base-content/55">
                    Durations use days, hours, minutes and seconds: 24h, 90m, or 1h 1s. Minimum 1m;
                    maximum 31d. Leave the contact ceiling blank for no overall ceiling. Settings
                    not shown here are preserved.
                  </p>
                  <div>
                    <p class="hud-label">Search boundary</p>
                    <div class="mt-3 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
                      <CadenceField
                        v-for="fieldKey in searchPolicyFieldKeys"
                        :key="policy_form.fields[fieldKey].id"
                        :control-id="policy_form.fields[fieldKey].id"
                        wrapper-class="fieldset mb-3"
                        :label="policy_form.fields[fieldKey].label"
                        label-class="hud-label block mb-1.5"
                      >
                        <input
                          :id="policy_form.fields[fieldKey].id"
                          v-model="policy[fieldKey]"
                          :name="policy_form.fields[fieldKey].name"
                          :aria-describedby="
                            fieldKey === 'max_horizon_duration'
                              ? 'fleet-policy-duration-help'
                              : undefined
                          "
                          :type="policy_form.fields[fieldKey].type"
                          :min="policy_form.fields[fieldKey].min ?? undefined"
                          :required="policy_form.fields[fieldKey].required"
                          :class="[
                            'w-full input',
                            policy_form.fields[fieldKey].errors.length > 0 && 'input-error',
                          ]"
                          @input="validatePolicy"
                        />
                        <template #errors>
                          <CadenceValidationMessage
                            v-for="error in policy_form.fields[fieldKey].errors"
                            :key="error"
                            >{{ error }}</CadenceValidationMessage
                          >
                        </template>
                      </CadenceField>
                    </div>
                  </div>

                  <div>
                    <p class="hud-label">Capacity & budget</p>
                    <div class="mt-3 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
                      <CadenceField
                        :control-id="policy_form.fields.max_contacts.id"
                        wrapper-class="fieldset mb-3"
                        :label="policy_form.fields.max_contacts.label"
                        label-class="hud-label block mb-1.5"
                      >
                        <input
                          :id="policy_form.fields.max_contacts.id"
                          v-model.number="policy.max_contacts"
                          :name="policy_form.fields.max_contacts.name"
                          type="number"
                          :min="policy_form.fields.max_contacts.min ?? undefined"
                          :required="policy_form.fields.max_contacts.required"
                          :class="[
                            'w-full input',
                            policy_form.fields.max_contacts.errors.length > 0 && 'input-error',
                          ]"
                          @input="validatePolicy"
                        />
                        <template #errors>
                          <CadenceValidationMessage
                            v-for="error in policy_form.fields.max_contacts.errors"
                            :key="error"
                            >{{ error }}</CadenceValidationMessage
                          >
                        </template>
                      </CadenceField>

                      <CadenceField
                        :control-id="policy_form.fields.max_estimated_cost_micros.id"
                        wrapper-class="fieldset mb-3"
                        :label="policy_form.fields.max_estimated_cost_micros.label"
                        label-class="hud-label block mb-1.5"
                      >
                        <input
                          :id="policy_form.fields.max_estimated_cost_micros.id"
                          v-model.number="policy.max_estimated_cost_micros"
                          :name="policy_form.fields.max_estimated_cost_micros.name"
                          type="number"
                          :min="policy_form.fields.max_estimated_cost_micros.min ?? undefined"
                          :class="[
                            'w-full input',
                            policy_form.fields.max_estimated_cost_micros.errors.length > 0 &&
                              'input-error',
                          ]"
                          @input="validatePolicy"
                        />
                        <template #errors>
                          <CadenceValidationMessage
                            v-for="error in policy_form.fields.max_estimated_cost_micros.errors"
                            :key="error"
                            >{{ error }}</CadenceValidationMessage
                          >
                        </template>
                      </CadenceField>

                      <CadenceField
                        :control-id="policy_form.fields.currency.id"
                        wrapper-class="fieldset mb-3"
                        :label="policy_form.fields.currency.label"
                        label-class="hud-label block mb-1.5"
                      >
                        <input
                          :id="policy_form.fields.currency.id"
                          v-model="policy.currency"
                          :name="policy_form.fields.currency.name"
                          type="text"
                          :class="[
                            'w-full input',
                            policy_form.fields.currency.errors.length > 0 && 'input-error',
                          ]"
                          @input="validatePolicy"
                        />
                        <template #errors>
                          <CadenceValidationMessage
                            v-for="error in policy_form.fields.currency.errors"
                            :key="error"
                            >{{ error }}</CadenceValidationMessage
                          >
                        </template>
                      </CadenceField>

                      <CadenceField
                        :control-id="policy_form.fields.critical_contact_reserve.id"
                        wrapper-class="fieldset mb-3"
                        :label="policy_form.fields.critical_contact_reserve.label"
                        label-class="hud-label block mb-1.5"
                      >
                        <input
                          :id="policy_form.fields.critical_contact_reserve.id"
                          v-model.number="policy.critical_contact_reserve"
                          :name="policy_form.fields.critical_contact_reserve.name"
                          type="number"
                          :min="policy_form.fields.critical_contact_reserve.min ?? undefined"
                          :required="policy_form.fields.critical_contact_reserve.required"
                          :class="[
                            'w-full input',
                            policy_form.fields.critical_contact_reserve.errors.length > 0 &&
                              'input-error',
                          ]"
                          @input="validatePolicy"
                        />
                        <template #errors>
                          <CadenceValidationMessage
                            v-for="error in policy_form.fields.critical_contact_reserve.errors"
                            :key="error"
                            >{{ error }}</CadenceValidationMessage
                          >
                        </template>
                      </CadenceField>
                    </div>
                  </div>

                  <div>
                    <p class="hud-label">Automation & repair</p>
                    <div class="mt-3 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
                      <CadenceField
                        :control-id="policy_form.fields.automation_mode.id"
                        wrapper-class="fieldset mb-3"
                        :label="policy_form.fields.automation_mode.label"
                        label-class="hud-label block mb-1.5"
                      >
                        <select
                          :id="policy_form.fields.automation_mode.id"
                          v-model="policy.automation_mode"
                          :name="policy_form.fields.automation_mode.name"
                          :class="[
                            'w-full select',
                            policy_form.fields.automation_mode.errors.length > 0 && 'select-error',
                          ]"
                          @change="validatePolicy"
                        >
                          <option
                            v-for="option in policy_form.fields.automation_mode.options"
                            :key="option.value"
                            :value="option.value"
                          >
                            {{ option.label }}
                          </option>
                        </select>
                        <template #errors>
                          <CadenceValidationMessage
                            v-for="error in policy_form.fields.automation_mode.errors"
                            :key="error"
                            >{{ error }}</CadenceValidationMessage
                          >
                        </template>
                      </CadenceField>

                      <CadenceField
                        v-for="fieldKey in automationPolicyFieldKeys"
                        :key="policy_form.fields[fieldKey].id"
                        :control-id="policy_form.fields[fieldKey].id"
                        wrapper-class="fieldset mb-3"
                        :label="policy_form.fields[fieldKey].label"
                        label-class="hud-label block mb-1.5"
                      >
                        <input
                          :id="policy_form.fields[fieldKey].id"
                          v-model="policy[fieldKey]"
                          :name="policy_form.fields[fieldKey].name"
                          :aria-describedby="
                            fieldKey === 'repair_horizon_duration'
                              ? 'fleet-policy-duration-help'
                              : undefined
                          "
                          :type="policy_form.fields[fieldKey].type"
                          :min="policy_form.fields[fieldKey].min ?? undefined"
                          :required="policy_form.fields[fieldKey].required"
                          :class="[
                            'w-full input',
                            policy_form.fields[fieldKey].errors.length > 0 && 'input-error',
                          ]"
                          @input="validatePolicy"
                        />
                        <template #errors>
                          <CadenceValidationMessage
                            v-for="error in policy_form.fields[fieldKey].errors"
                            :key="error"
                            >{{ error }}</CadenceValidationMessage
                          >
                        </template>
                      </CadenceField>
                    </div>

                    <div v-if="policy.automation_mode !== 'advisory'" class="fieldset mb-3">
                      <label class="flex cursor-pointer items-start gap-3">
                        <input
                          type="hidden"
                          :name="policy_form.fields.automatic_submission.name"
                          value="false"
                        />
                        <input
                          :id="policy_form.fields.automatic_submission.id"
                          v-model="policy.automatic_submission"
                          :name="policy_form.fields.automatic_submission.name"
                          value="true"
                          type="checkbox"
                          class="checkbox checkbox-sm mt-0.5"
                          @change="validatePolicy"
                        />
                        <span>
                          <span class="block text-sm font-medium">{{
                            policy_form.fields.automatic_submission.label
                          }}</span>
                        </span>
                      </label>
                    </div>
                  </div>

                  <CadenceDetailsFrame
                    :id="policy_form.redundancy.id"
                    class="border border-base-300"
                  >
                    <summary class="cursor-pointer px-3 py-2 text-xs font-semibold">
                      {{ policy_form.redundancy.summary }}
                    </summary>
                    <div class="grid gap-3 border-t border-base-300 p-3 sm:grid-cols-3">
                      <div
                        v-for="fieldKey in redundancyPolicyFieldKeys"
                        :key="policy_form.fields[fieldKey].id"
                        class="fieldset mb-3"
                      >
                        <label class="flex cursor-pointer items-start gap-3">
                          <input
                            type="hidden"
                            :name="policy_form.fields[fieldKey].name"
                            value="false"
                          />
                          <input
                            :id="policy_form.fields[fieldKey].id"
                            v-model="policy[fieldKey]"
                            :name="policy_form.fields[fieldKey].name"
                            value="true"
                            type="checkbox"
                            class="checkbox checkbox-sm mt-0.5"
                            @change="validatePolicy"
                          />
                          <span>
                            <span class="block text-sm font-medium">{{
                              policy_form.fields[fieldKey].label
                            }}</span>
                          </span>
                        </label>
                      </div>
                    </div>
                  </CadenceDetailsFrame>

                  <button
                    :id="policy_form.submit.id"
                    :disabled="!canSavePolicy"
                    type="submit"
                    class="btn btn-primary btn-sm w-full"
                  >
                    {{ policy_form.submit.label }}
                  </button>
                </form>
              </CadenceCollapsibleContent>
            </div>
          </CadenceCollapsible>
        </section>

        <section
          v-if="approval_form"
          :id="approval_form.panel_id"
          class="border border-primary/35 bg-primary/[0.035] p-4"
        >
          <p class="hud-label">Activate exact version</p>
          <p class="mt-2 text-sm text-base-content/60">
            Approval invalidates grants tied to an older policy version and changes the boundary for
            future runs.
          </p>
          <form :id="approval_form.id" class="mt-4" @submit.prevent="approvePolicy">
            <CadenceField
              :control-id="approval_form.reason.id"
              wrapper-class="fieldset mb-3"
              :label="approval_form.reason.label"
              label-class="hud-label block mb-1.5"
            >
              <textarea
                :id="approval_form.reason.id"
                v-model="approvalReason"
                :name="approval_form.reason.name"
                :required="approval_form.reason.required"
                :class="[
                  'w-full textarea',
                  approval_form.reason.errors.length > 0 && 'textarea-error',
                ]"
              ></textarea>
              <template #errors>
                <CadenceValidationMessage
                  v-for="error in approval_form.reason.errors"
                  :key="error"
                  >{{ error }}</CadenceValidationMessage
                >
              </template>
            </CadenceField>
            <button
              :id="approval_form.submit.id"
              :disabled="!approvalEvidence"
              type="submit"
              class="btn btn-primary btn-sm w-full"
            >
              {{ approval_form.submit.label }}
            </button>
          </form>
        </section>
      </div>

      <aside class="min-w-0 space-y-5">
        <CadencePanel
          :id="grant_ledger.id"
          class="border border-base-300 bg-base-200/15"
          header-class="flex items-center justify-between border-b border-base-300 px-4 py-3"
        >
          <template #header>
            <div>
              <p class="hud-label">Automation grants</p>
              <p class="mt-1 text-xs text-base-content/50">Exact service + policy authority</p>
            </div>
            <span class="font-mono text-xs text-base-content/45">{{
              grant_ledger.active_label
            }}</span>
          </template>
          <div :id="grant_ledger.list_id">
            <div
              :id="grant_ledger.empty.id"
              class="hidden only:block px-4 py-10 text-center text-sm text-base-content/50"
            >
              {{ grant_ledger.empty.copy }}
            </div>
            <div
              v-for="automationGrant in automation_grants"
              :id="automationGrant.__dom_id"
              :key="automationGrant.automation_grant_id"
              class="border-b border-base-300 p-4 last:border-b-0"
            >
              <div class="flex items-center justify-between gap-3">
                <p class="truncate text-xs font-semibold">
                  {{ automationGrant.service_identity_id }}
                </p>
                <span :class="automationGrant.lifecycle_state_class">
                  {{ automationGrant.lifecycle_state }}
                </span>
              </div>
              <p class="mt-2 font-mono text-[0.58rem] text-base-content/40">
                {{ automationGrant.policy_evidence }}
              </p>
              <p class="mt-2 text-xs text-base-content/55">{{ automationGrant.boundary }}</p>
              <p class="mt-2 font-mono text-[0.56rem] text-base-content/35">
                {{ automationGrant.expiry }}
              </p>
            </div>
          </div>
        </CadencePanel>

        <section
          v-if="grant_form"
          :id="grant_form.panel_id"
          class="border border-base-300 bg-base-200/15"
        >
          <CadenceDetailsFrame>
            <summary class="cursor-pointer px-4 py-3 text-sm font-semibold">
              Issue bounded authority
            </summary>
            <form
              :id="grant_form.id"
              class="space-y-4 border-t border-base-300 p-4"
              @submit.prevent="issueGrant"
            >
              <div
                v-if="grantStale"
                id="fleet-grant-edit-unavailable"
                class="space-y-2 border border-warning/40 p-3 text-sm"
                role="alert"
              >
                <p>
                  The approved policy changed. Your grant inputs are retained; load the current
                  policy before issuing authority.
                </p>
                <button
                  id="fleet-grant-load-current"
                  type="button"
                  class="btn btn-sm"
                  @click="loadCurrentGrant"
                >
                  Load current approved policy
                </button>
              </div>
              <p
                v-if="grantEvidence"
                id="automation-grant-policy-evidence"
                class="break-all font-mono text-xs text-base-content/60"
              >
                Approved policy v{{ grantEvidence.policy_version }} ·
                {{ grantEvidence.content_sha256 }}
              </p>
              <CadenceField
                :control-id="grant_form.fields.service_identity_id.id"
                wrapper-class="fieldset mb-3"
                :label="grant_form.fields.service_identity_id.label"
                label-class="hud-label block mb-1.5"
              >
                <select
                  :id="grant_form.fields.service_identity_id.id"
                  v-model="grant.service_identity_id"
                  :name="grant_form.fields.service_identity_id.name"
                  :required="grant_form.fields.service_identity_id.required"
                  :class="[
                    'w-full select',
                    grant_form.fields.service_identity_id.errors.length > 0 && 'select-error',
                  ]"
                  @change="validateGrant"
                >
                  <option
                    v-for="option in grant_form.fields.service_identity_id.options"
                    :key="option.value"
                    :value="option.value"
                  >
                    {{ option.label }}
                  </option>
                </select>
                <template #errors>
                  <CadenceValidationMessage
                    v-for="error in grant_form.fields.service_identity_id.errors"
                    :key="error"
                    >{{ error }}</CadenceValidationMessage
                  >
                </template>
              </CadenceField>

              <div class="grid gap-3 sm:grid-cols-2">
                <CadenceField
                  :control-id="grant_form.fields.maximum_horizon_duration.id"
                  wrapper-class="fieldset mb-3"
                  :label="grant_form.fields.maximum_horizon_duration.label"
                  label-class="hud-label block mb-1.5"
                >
                  <input
                    :id="grant_form.fields.maximum_horizon_duration.id"
                    v-model="grant.maximum_horizon_duration"
                    :name="grant_form.fields.maximum_horizon_duration.name"
                    :type="grant_form.fields.maximum_horizon_duration.type"
                    aria-describedby="automation-grant-duration-help"
                    :min="grant_form.fields.maximum_horizon_duration.min ?? undefined"
                    :required="grant_form.fields.maximum_horizon_duration.required"
                    :class="[
                      'w-full input',
                      grant_form.fields.maximum_horizon_duration.errors.length > 0 && 'input-error',
                    ]"
                    @input="validateGrant"
                  />
                  <template #help>
                    <p
                      id="automation-grant-duration-help"
                      class="mt-1 text-xs text-base-content/55"
                    >
                      Use 24h, 90m, or 1h 1s. The grant must stay within the approved policy
                      horizon.
                    </p>
                  </template>
                  <template #errors>
                    <CadenceValidationMessage
                      v-for="error in grant_form.fields.maximum_horizon_duration.errors"
                      :key="error"
                      >{{ error }}</CadenceValidationMessage
                    >
                  </template>
                </CadenceField>

                <CadenceField
                  :control-id="grant_form.fields.maximum_contacts.id"
                  wrapper-class="fieldset mb-3"
                  :label="grant_form.fields.maximum_contacts.label"
                  label-class="hud-label block mb-1.5"
                >
                  <input
                    :id="grant_form.fields.maximum_contacts.id"
                    v-model.number="grant.maximum_contacts"
                    :name="grant_form.fields.maximum_contacts.name"
                    type="number"
                    :min="grant_form.fields.maximum_contacts.min ?? undefined"
                    :required="grant_form.fields.maximum_contacts.required"
                    :class="[
                      'w-full input',
                      grant_form.fields.maximum_contacts.errors.length > 0 && 'input-error',
                    ]"
                    @input="validateGrant"
                  />
                  <template #errors>
                    <CadenceValidationMessage
                      v-for="error in grant_form.fields.maximum_contacts.errors"
                      :key="error"
                      >{{ error }}</CadenceValidationMessage
                    >
                  </template>
                </CadenceField>

                <CadenceField
                  :control-id="grant_form.fields.maximum_execution_concurrency.id"
                  wrapper-class="fieldset mb-3"
                  :label="grant_form.fields.maximum_execution_concurrency.label"
                  label-class="hud-label block mb-1.5"
                >
                  <input
                    :id="grant_form.fields.maximum_execution_concurrency.id"
                    v-model.number="grant.maximum_execution_concurrency"
                    :name="grant_form.fields.maximum_execution_concurrency.name"
                    type="number"
                    :min="grant_form.fields.maximum_execution_concurrency.min ?? undefined"
                    :required="grant_form.fields.maximum_execution_concurrency.required"
                    :class="[
                      'w-full input',
                      grant_form.fields.maximum_execution_concurrency.errors.length > 0 &&
                        'input-error',
                    ]"
                    @input="validateGrant"
                  />
                  <template #errors>
                    <CadenceValidationMessage
                      v-for="error in grant_form.fields.maximum_execution_concurrency.errors"
                      :key="error"
                      >{{ error }}</CadenceValidationMessage
                    >
                  </template>
                </CadenceField>

                <CadenceField
                  :control-id="grant_form.fields.valid_days.id"
                  wrapper-class="fieldset mb-3"
                  :label="grant_form.fields.valid_days.label"
                  label-class="hud-label block mb-1.5"
                >
                  <input
                    :id="grant_form.fields.valid_days.id"
                    v-model.number="grant.valid_days"
                    :name="grant_form.fields.valid_days.name"
                    type="number"
                    :min="grant_form.fields.valid_days.min ?? undefined"
                    :required="grant_form.fields.valid_days.required"
                    :class="[
                      'w-full input',
                      grant_form.fields.valid_days.errors.length > 0 && 'input-error',
                    ]"
                    @input="validateGrant"
                  />
                  <template #errors>
                    <CadenceValidationMessage
                      v-for="error in grant_form.fields.valid_days.errors"
                      :key="error"
                      >{{ error }}</CadenceValidationMessage
                    >
                  </template>
                </CadenceField>
              </div>

              <CadenceField
                :control-id="grant_form.fields.approval_reason.id"
                wrapper-class="fieldset mb-3"
                :label="grant_form.fields.approval_reason.label"
                label-class="hud-label block mb-1.5"
              >
                <textarea
                  :id="grant_form.fields.approval_reason.id"
                  v-model="grant.approval_reason"
                  :name="grant_form.fields.approval_reason.name"
                  :required="grant_form.fields.approval_reason.required"
                  :class="[
                    'w-full textarea',
                    grant_form.fields.approval_reason.errors.length > 0 && 'textarea-error',
                  ]"
                  @input="validateGrant"
                ></textarea>
                <template #errors>
                  <CadenceValidationMessage
                    v-for="error in grant_form.fields.approval_reason.errors"
                    :key="error"
                    >{{ error }}</CadenceValidationMessage
                  >
                </template>
              </CadenceField>

              <button
                :id="grant_form.submit.id"
                :disabled="!grantEvidence || grantStale"
                type="submit"
                class="btn btn-primary btn-sm w-full"
              >
                {{ grant_form.submit.label }}
              </button>
            </form>
          </CadenceDetailsFrame>
        </section>

        <section
          v-if="revocation_form"
          :id="revocation_form.panel_id"
          class="border border-error/25 bg-error/[0.025]"
        >
          <CadenceDetailsFrame>
            <summary class="cursor-pointer px-4 py-3 text-sm font-semibold text-error">
              Revoke automation authority
            </summary>
            <form
              :id="revocation_form.id"
              class="space-y-3 border-t border-error/20 p-4"
              @submit.prevent="revokeGrant"
            >
              <CadenceField
                :control-id="revocation_form.fields.automation_grant_id.id"
                wrapper-class="fieldset mb-3"
                :label="revocation_form.fields.automation_grant_id.label"
                label-class="hud-label block mb-1.5"
              >
                <select
                  :id="revocation_form.fields.automation_grant_id.id"
                  v-model="revocation.automation_grant_id"
                  :name="revocation_form.fields.automation_grant_id.name"
                  :required="revocation_form.fields.automation_grant_id.required"
                  :class="[
                    'w-full select',
                    revocation_form.fields.automation_grant_id.errors.length > 0 && 'select-error',
                  ]"
                >
                  <option
                    v-for="option in revocation_form.fields.automation_grant_id.options"
                    :key="option.value"
                    :value="option.value"
                  >
                    {{ option.label }}
                  </option>
                </select>
                <template #errors>
                  <CadenceValidationMessage
                    v-for="error in revocation_form.fields.automation_grant_id.errors"
                    :key="error"
                    >{{ error }}</CadenceValidationMessage
                  >
                </template>
              </CadenceField>

              <CadenceField
                :control-id="revocation_form.fields.reason.id"
                wrapper-class="fieldset mb-3"
                :label="revocation_form.fields.reason.label"
                label-class="hud-label block mb-1.5"
              >
                <textarea
                  :id="revocation_form.fields.reason.id"
                  v-model="revocation.reason"
                  :name="revocation_form.fields.reason.name"
                  :required="revocation_form.fields.reason.required"
                  :class="[
                    'w-full textarea',
                    revocation_form.fields.reason.errors.length > 0 && 'textarea-error',
                  ]"
                ></textarea>
                <template #errors>
                  <CadenceValidationMessage
                    v-for="error in revocation_form.fields.reason.errors"
                    :key="error"
                    >{{ error }}</CadenceValidationMessage
                  >
                </template>
              </CadenceField>

              <button
                :id="revocation_form.submit.id"
                type="submit"
                class="btn btn-error btn-sm w-full"
              >
                {{ revocation_form.submit.label }}
              </button>
            </form>
          </CadenceDetailsFrame>
        </section>

        <CadenceInlineWarning
          v-if="(approval_form && !approvalEvidence) || (grant_form && !grantEvidence)"
          id="fleet-policy-evidence-unavailable"
        >
          Policy evidence is unavailable or inconsistent. Refresh this page before approving policy
          or issuing automation authority.
        </CadenceInlineWarning>
        <CadenceInlineWarning v-if="authorization.admin_required">
          {{ authorization.admin_required.copy }}
        </CadenceInlineWarning>
      </aside>
    </div>
  </section>
</template>
