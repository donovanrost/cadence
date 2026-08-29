<script setup lang="ts">
import CadenceField from "./ui/components/CadenceField.vue"
import CadenceDetailsFrame from "./ui/components/CadenceDetailsFrame.vue"
import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"
import CadenceValidationMessage from "./ui/components/CadenceValidationMessage.vue"
import {reactive, ref, watch} from "vue"
import CadencePanel from "./ui/components/CadencePanel.vue"

type Option = {
  label: string
  value: string
}

type FormField = {
  id: string
  name: string
  type: "text" | "number" | "select" | "textarea"
  label: string
  required: boolean
  min: number | null
  options: Option[]
  value: string
  errors: string[]
}

type CheckboxField = {
  id: string
  name: string
  type: "checkbox"
  label: string
  value: boolean
  errors: string[]
}

type PolicyForm = {
  panel_id: string
  id: string
  open: boolean
  summary: string
  fields: {
    max_horizon_hours: FormField
    requirement_concurrency: FormField
    provider_search_concurrency: FormField
    reuse_freshness_seconds: FormField
    max_contacts: FormField
    max_estimated_cost_micros: FormField
    currency: FormField
    critical_contact_reserve: FormField
    automation_mode: FormField
    execution_concurrency: FormField
    max_repair_attempts: FormField
    repair_horizon_hours: FormField
    automatic_submission: CheckboxField
    distinct_provider_required: CheckboxField
    distinct_station_required: CheckboxField
    distinct_service_pool_required: CheckboxField
  }
  redundancy: {
    id: string
    summary: string
  }
  submit: {
    id: string
    label: string
  }
}

type ApprovalForm = {
  panel_id: string
  id: string
  reason: FormField
  submit: {
    id: string
    label: string
  }
}

type GrantForm = {
  panel_id: string
  id: string
  fields: {
    service_identity_id: FormField
    maximum_horizon_hours: FormField
    maximum_contacts: FormField
    maximum_execution_concurrency: FormField
    valid_days: FormField
    approval_reason: FormField
  }
  submit: {
    id: string
    label: string
  }
}

type RevocationForm = {
  panel_id: string
  id: string
  fields: {
    automation_grant_id: FormField
    reason: FormField
  }
  submit: {
    id: string
    label: string
  }
}

type AutomationGrant = {
  __dom_id: string
  automation_grant_id: string
  service_identity_id: string
  lifecycle_state: string
  lifecycle_state_class: string
  policy_evidence: string
  boundary: string
  expiry: string
}

type PolicyValues = {
  max_horizon_hours: string | number
  requirement_concurrency: string | number
  provider_search_concurrency: string | number
  reuse_freshness_seconds: string | number
  max_contacts: string | number
  max_estimated_cost_micros: string | number
  currency: string
  critical_contact_reserve: string | number
  automation_mode: string
  execution_concurrency: string | number
  max_repair_attempts: string | number
  repair_horizon_hours: string | number
  automatic_submission: boolean
  distinct_provider_required: boolean
  distinct_station_required: boolean
  distinct_service_pool_required: boolean
}

type GrantValues = {
  service_identity_id: string
  maximum_horizon_hours: string | number
  maximum_contacts: string | number
  maximum_execution_concurrency: string | number
  valid_days: string | number
  approval_reason: string
}

type StringPayload = Record<string, string>

const props = defineProps<{
  page: {
    back: {
      href: string
      icon: string
      label: string
    }
    header: {
      eyebrow: string
      title: string
      copy: string
    }
    state: {
      id: string
      label: string
      class: string
    }
    manifest: {
      id: string
      version_label: string
      content_sha256: string | null
      sections: Array<{
        title: string
        facts: Array<{
          term: string
          value: string
        }>
      }>
      empty: {
        id: string
        icon: string
        title: string
        copy: string
      } | null
    }
  }
  policy_form: PolicyForm | null
  approval_form: ApprovalForm | null
  authorization: {
    organization_admin: boolean
    admin_required: {
      copy: string
    } | null
  }
  grant_ledger: {
    id: string
    list_id: string
    empty: {
      id: string
      copy: string
    }
    active_count: number
    active_label: string
  }
  grant_form: GrantForm | null
  revocation_form: RevocationForm | null
  automation_grants: AutomationGrant[]
}>()

const emit = defineEmits<{
  "validate-policy": [payload: {policy: StringPayload}]
  "save-policy": [payload: {policy: StringPayload}]
  "approve-policy": [payload: {decision: {reason: string}}]
  "validate-grant": [payload: {grant: StringPayload}]
  "issue-grant": [payload: {grant: StringPayload}]
  "revoke-grant": [payload: {revocation: {automation_grant_id: string; reason: string}}]
}>()

const searchPolicyFieldKeys = [
  "max_horizon_hours",
  "requirement_concurrency",
  "provider_search_concurrency",
  "reuse_freshness_seconds"
] as const

const automationPolicyFieldKeys = [
  "execution_concurrency",
  "max_repair_attempts",
  "repair_horizon_hours"
] as const

const redundancyPolicyFieldKeys = [
  "distinct_provider_required",
  "distinct_station_required",
  "distinct_service_pool_required"
] as const

const emptyPolicyValues = (): PolicyValues => ({
  max_horizon_hours: "",
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
  repair_horizon_hours: "",
  automatic_submission: false,
  distinct_provider_required: false,
  distinct_station_required: false,
  distinct_service_pool_required: false
})

const policyValuesFromForm = (form: PolicyForm | null): PolicyValues => {
  if (!form) return emptyPolicyValues()

  return {
    max_horizon_hours: form.fields.max_horizon_hours.value,
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
    repair_horizon_hours: form.fields.repair_horizon_hours.value,
    automatic_submission: form.fields.automatic_submission.value,
    distinct_provider_required: form.fields.distinct_provider_required.value,
    distinct_station_required: form.fields.distinct_station_required.value,
    distinct_service_pool_required: form.fields.distinct_service_pool_required.value
  }
}

const stringValue = (value: string | number) => String(value ?? "")
const checkboxValue = (value: boolean) => value ? "true" : "false"

const normalizedPolicy = (values: PolicyValues): StringPayload => {
  const normalized: StringPayload = {
    max_horizon_hours: stringValue(values.max_horizon_hours),
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
    repair_horizon_hours: stringValue(values.repair_horizon_hours),
    distinct_provider_required: checkboxValue(values.distinct_provider_required),
    distinct_station_required: checkboxValue(values.distinct_station_required),
    distinct_service_pool_required: checkboxValue(values.distinct_service_pool_required)
  }

  if (values.automation_mode !== "advisory") {
    normalized.automatic_submission = checkboxValue(values.automatic_submission)
  }

  return normalized
}

const policy = reactive<PolicyValues>(policyValuesFromForm(props.policy_form))
const pendingPolicyValidations: StringPayload[] = []
const samePayload = (left: StringPayload, right: StringPayload) =>
  JSON.stringify(left) === JSON.stringify(right)

watch(
  () => props.policy_form,
  (serverForm) => {
    if (!serverForm) return

    const serverValues = policyValuesFromForm(serverForm)
    const serverPayload = normalizedPolicy(serverValues)
    const acknowledgedIndex = pendingPolicyValidations.findIndex((sent) =>
      samePayload(sent, serverPayload)
    )
    const hasNewerTyping =
      acknowledgedIndex >= 0 && acknowledgedIndex < pendingPolicyValidations.length - 1

    if (acknowledgedIndex >= 0) pendingPolicyValidations.splice(0, acknowledgedIndex + 1)
    if (!hasNewerTyping) Object.assign(policy, serverValues)
  },
  {deep: true}
)

const validatePolicy = () => {
  const values = normalizedPolicy(policy)
  pendingPolicyValidations.push(values)
  emit("validate-policy", {policy: values})
}

const savePolicy = () => emit("save-policy", {policy: normalizedPolicy(policy)})

const approvalReason = ref(props.approval_form?.reason.value ?? "")

watch(
  () => props.approval_form?.reason.value ?? "",
  (reason) => {
    approvalReason.value = reason
  }
)

const approvePolicy = () => {
  emit("approve-policy", {decision: {reason: approvalReason.value}})
}

const emptyGrantValues = (): GrantValues => ({
  service_identity_id: "",
  maximum_horizon_hours: "",
  maximum_contacts: "",
  maximum_execution_concurrency: "",
  valid_days: "",
  approval_reason: ""
})

const grantValuesFromForm = (form: GrantForm | null): GrantValues => {
  if (!form) return emptyGrantValues()

  return {
    service_identity_id: form.fields.service_identity_id.value,
    maximum_horizon_hours: form.fields.maximum_horizon_hours.value,
    maximum_contacts: form.fields.maximum_contacts.value,
    maximum_execution_concurrency: form.fields.maximum_execution_concurrency.value,
    valid_days: form.fields.valid_days.value,
    approval_reason: form.fields.approval_reason.value
  }
}

const normalizedGrant = (values: GrantValues): StringPayload => ({
  service_identity_id: values.service_identity_id,
  maximum_horizon_hours: stringValue(values.maximum_horizon_hours),
  maximum_contacts: stringValue(values.maximum_contacts),
  maximum_execution_concurrency: stringValue(values.maximum_execution_concurrency),
  valid_days: stringValue(values.valid_days),
  approval_reason: values.approval_reason
})

const grant = reactive<GrantValues>(grantValuesFromForm(props.grant_form))
const pendingGrantValidations: StringPayload[] = []

watch(
  () => props.grant_form,
  (serverForm) => {
    if (!serverForm) return

    const serverValues = grantValuesFromForm(serverForm)
    const serverPayload = normalizedGrant(serverValues)
    const acknowledgedIndex = pendingGrantValidations.findIndex((sent) =>
      samePayload(sent, serverPayload)
    )
    const hasNewerTyping =
      acknowledgedIndex >= 0 && acknowledgedIndex < pendingGrantValidations.length - 1

    if (acknowledgedIndex >= 0) pendingGrantValidations.splice(0, acknowledgedIndex + 1)
    if (!hasNewerTyping) Object.assign(grant, serverValues)
  },
  {deep: true}
)

const validateGrant = () => {
  const values = normalizedGrant(grant)
  pendingGrantValidations.push(values)
  emit("validate-grant", {grant: values})
}

const issueGrant = () => emit("issue-grant", {grant: normalizedGrant(grant)})

const revocation = reactive({automation_grant_id: "", reason: ""})

watch(
  () => props.revocation_form,
  (serverForm) => {
    if (!serverForm) {
      Object.assign(revocation, {automation_grant_id: "", reason: ""})
      return
    }

    Object.assign(revocation, {
      automation_grant_id:
        serverForm.fields.automation_grant_id.value ||
        serverForm.fields.automation_grant_id.options[0]?.value ||
        "",
      reason: serverForm.fields.reason.value
    })
  },
  {deep: true, immediate: true}
)

const revokeGrant = () => {
  emit("revoke-grant", {
    revocation: {
      automation_grant_id: revocation.automation_grant_id,
      reason: revocation.reason
    }
  })
}
</script>

<template>
  <CadencePageHeaderFrame variant="ops">
    <div class="mx-auto max-w-[100rem]">
      <a
        :href="page.back.href"
        data-phx-link="redirect"
        data-phx-link-state="push"
        class="inline-flex items-center gap-1 font-mono text-xs text-base-content/55 hover:text-primary"
      >
        <span :class="[page.back.icon, 'h-3.5 w-3.5']"></span>
        {{ page.back.label }}
      </a>
      <div class="mt-4 flex flex-col gap-4 md:flex-row md:items-end md:justify-between">
        <div>
          <p class="font-mono text-[0.65rem] uppercase tracking-[0.28em] text-primary/70">
            {{ page.header.eyebrow }}
          </p>
          <h1 class="mt-1 text-2xl font-bold tracking-tight">{{ page.header.title }}</h1>
          <p class="mt-2 max-w-3xl text-sm text-base-content/60">
            {{ page.header.copy }}
          </p>
        </div>
        <span :id="page.state.id" :class="page.state.class">
          {{ page.state.label }}
        </span>
      </div>
    </div>
  </CadencePageHeaderFrame>

  <div class="mx-auto grid max-w-[100rem] gap-5 p-5 xl:grid-cols-[minmax(0,1.25fr)_minmax(24rem,0.75fr)] lg:p-7">
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
        <details :open="policy_form.open">
          <summary class="cursor-pointer px-4 py-3 text-sm font-semibold">
            {{ policy_form.summary }}
          </summary>
          <form
            :id="policy_form.id"
            class="space-y-5 border-t border-base-300 p-4"
            @submit.prevent="savePolicy"
          >
            <div>
              <p class="hud-label">Search boundary</p>
              <div class="mt-3 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
                <div
                  v-for="fieldKey in searchPolicyFieldKeys"
                  :key="policy_form.fields[fieldKey].id"
                  class="fieldset mb-3"
                >
                  <label :for="policy_form.fields[fieldKey].id">
                    <span class="hud-label block mb-1.5">{{ policy_form.fields[fieldKey].label }}</span>
                    <input
                      :id="policy_form.fields[fieldKey].id"
                      v-model.number="policy[fieldKey]"
                      :name="policy_form.fields[fieldKey].name"
                      :type="policy_form.fields[fieldKey].type"
                      :min="policy_form.fields[fieldKey].min ?? undefined"
                      :required="policy_form.fields[fieldKey].required"
                      :class="['w-full input', policy_form.fields[fieldKey].errors.length > 0 && 'input-error']"
                      @input="validatePolicy"
                    >
                  </label>
                  <CadenceValidationMessage
                    v-for="error in policy_form.fields[fieldKey].errors"
                    :key="error"
                  >{{ error }}</CadenceValidationMessage>
                </div>
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
                    :class="['w-full input', policy_form.fields.max_contacts.errors.length > 0 && 'input-error']"
                    @input="validatePolicy"
                  >
                  <template #errors>
                    <CadenceValidationMessage v-for="error in policy_form.fields.max_contacts.errors" :key="error">{{ error }}</CadenceValidationMessage>
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
                    :class="['w-full input', policy_form.fields.max_estimated_cost_micros.errors.length > 0 && 'input-error']"
                    @input="validatePolicy"
                  >
                  <template #errors>
                    <CadenceValidationMessage v-for="error in policy_form.fields.max_estimated_cost_micros.errors" :key="error">{{ error }}</CadenceValidationMessage>
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
                    :class="['w-full input', policy_form.fields.currency.errors.length > 0 && 'input-error']"
                    @input="validatePolicy"
                  >
                  <template #errors>
                    <CadenceValidationMessage v-for="error in policy_form.fields.currency.errors" :key="error">{{ error }}</CadenceValidationMessage>
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
                    :class="['w-full input', policy_form.fields.critical_contact_reserve.errors.length > 0 && 'input-error']"
                    @input="validatePolicy"
                  >
                  <template #errors>
                    <CadenceValidationMessage v-for="error in policy_form.fields.critical_contact_reserve.errors" :key="error">{{ error }}</CadenceValidationMessage>
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
                    :class="['w-full select', policy_form.fields.automation_mode.errors.length > 0 && 'select-error']"
                    @change="validatePolicy"
                  >
                    <option
                      v-for="option in policy_form.fields.automation_mode.options"
                      :key="option.value"
                      :value="option.value"
                    >{{ option.label }}</option>
                  </select>
                  <template #errors>
                    <CadenceValidationMessage v-for="error in policy_form.fields.automation_mode.errors" :key="error">{{ error }}</CadenceValidationMessage>
                  </template>
                </CadenceField>

                <div
                  v-for="fieldKey in automationPolicyFieldKeys"
                  :key="policy_form.fields[fieldKey].id"
                  class="fieldset mb-3"
                >
                  <label :for="policy_form.fields[fieldKey].id">
                    <span class="hud-label block mb-1.5">{{ policy_form.fields[fieldKey].label }}</span>
                    <input
                      :id="policy_form.fields[fieldKey].id"
                      v-model.number="policy[fieldKey]"
                      :name="policy_form.fields[fieldKey].name"
                      type="number"
                      :min="policy_form.fields[fieldKey].min ?? undefined"
                      :required="policy_form.fields[fieldKey].required"
                      :class="['w-full input', policy_form.fields[fieldKey].errors.length > 0 && 'input-error']"
                      @input="validatePolicy"
                    >
                  </label>
                  <CadenceValidationMessage v-for="error in policy_form.fields[fieldKey].errors" :key="error">{{ error }}</CadenceValidationMessage>
                </div>
              </div>

              <div v-if="policy.automation_mode !== 'advisory'" class="fieldset mb-3">
                <label class="flex cursor-pointer items-start gap-3">
                  <input type="hidden" :name="policy_form.fields.automatic_submission.name" value="false">
                  <input
                    :id="policy_form.fields.automatic_submission.id"
                    v-model="policy.automatic_submission"
                    :name="policy_form.fields.automatic_submission.name"
                    value="true"
                    type="checkbox"
                    class="checkbox checkbox-sm mt-0.5"
                    @change="validatePolicy"
                  >
                  <span>
                    <span class="block text-sm font-medium">{{ policy_form.fields.automatic_submission.label }}</span>
                  </span>
                </label>
              </div>
            </div>

            <CadenceDetailsFrame :id="policy_form.redundancy.id" class="border border-base-300">
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
                    <input type="hidden" :name="policy_form.fields[fieldKey].name" value="false">
                    <input
                      :id="policy_form.fields[fieldKey].id"
                      v-model="policy[fieldKey]"
                      :name="policy_form.fields[fieldKey].name"
                      value="true"
                      type="checkbox"
                      class="checkbox checkbox-sm mt-0.5"
                      @change="validatePolicy"
                    >
                    <span>
                      <span class="block text-sm font-medium">{{ policy_form.fields[fieldKey].label }}</span>
                    </span>
                  </label>
                </div>
              </div>
            </CadenceDetailsFrame>

            <button :id="policy_form.submit.id" type="submit" class="btn btn-primary btn-sm w-full">
              {{ policy_form.submit.label }}
            </button>
          </form>
        </details>
      </section>

      <section
        v-if="approval_form"
        :id="approval_form.panel_id"
        class="border border-primary/35 bg-primary/[0.035] p-4"
      >
        <p class="hud-label">Activate exact version</p>
        <p class="mt-2 text-sm text-base-content/60">
          Approval invalidates grants tied to an older policy version and changes the boundary for future runs.
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
              :class="['w-full textarea', approval_form.reason.errors.length > 0 && 'textarea-error']"
            ></textarea>
            <template #errors>
              <CadenceValidationMessage v-for="error in approval_form.reason.errors" :key="error">{{ error }}</CadenceValidationMessage>
            </template>
          </CadenceField>
          <button :id="approval_form.submit.id" type="submit" class="btn btn-primary btn-sm w-full">
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
          <span class="font-mono text-xs text-base-content/45">{{ grant_ledger.active_label }}</span>
        </template>
        <div :id="grant_ledger.list_id">
          <div :id="grant_ledger.empty.id" class="hidden only:block px-4 py-10 text-center text-sm text-base-content/50">
            {{ grant_ledger.empty.copy }}
          </div>
          <div
            v-for="automationGrant in automation_grants"
            :id="automationGrant.__dom_id"
            :key="automationGrant.automation_grant_id"
            class="border-b border-base-300 p-4 last:border-b-0"
          >
            <div class="flex items-center justify-between gap-3">
              <p class="truncate text-xs font-semibold">{{ automationGrant.service_identity_id }}</p>
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
                :class="['w-full select', grant_form.fields.service_identity_id.errors.length > 0 && 'select-error']"
                @change="validateGrant"
              >
                <option
                  v-for="option in grant_form.fields.service_identity_id.options"
                  :key="option.value"
                  :value="option.value"
                >{{ option.label }}</option>
              </select>
              <template #errors>
                <CadenceValidationMessage v-for="error in grant_form.fields.service_identity_id.errors" :key="error">{{ error }}</CadenceValidationMessage>
              </template>
            </CadenceField>

            <div class="grid gap-3 sm:grid-cols-2">
              <CadenceField
                :control-id="grant_form.fields.maximum_horizon_hours.id"
                wrapper-class="fieldset mb-3"
                :label="grant_form.fields.maximum_horizon_hours.label"
                label-class="hud-label block mb-1.5"
              >
                <input
                  :id="grant_form.fields.maximum_horizon_hours.id"
                  v-model.number="grant.maximum_horizon_hours"
                  :name="grant_form.fields.maximum_horizon_hours.name"
                  type="number"
                  :min="grant_form.fields.maximum_horizon_hours.min ?? undefined"
                  :required="grant_form.fields.maximum_horizon_hours.required"
                  :class="['w-full input', grant_form.fields.maximum_horizon_hours.errors.length > 0 && 'input-error']"
                  @input="validateGrant"
                >
                <template #errors>
                  <CadenceValidationMessage v-for="error in grant_form.fields.maximum_horizon_hours.errors" :key="error">{{ error }}</CadenceValidationMessage>
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
                  :class="['w-full input', grant_form.fields.maximum_contacts.errors.length > 0 && 'input-error']"
                  @input="validateGrant"
                >
                <template #errors>
                  <CadenceValidationMessage v-for="error in grant_form.fields.maximum_contacts.errors" :key="error">{{ error }}</CadenceValidationMessage>
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
                  :class="['w-full input', grant_form.fields.maximum_execution_concurrency.errors.length > 0 && 'input-error']"
                  @input="validateGrant"
                >
                <template #errors>
                  <CadenceValidationMessage v-for="error in grant_form.fields.maximum_execution_concurrency.errors" :key="error">{{ error }}</CadenceValidationMessage>
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
                  :class="['w-full input', grant_form.fields.valid_days.errors.length > 0 && 'input-error']"
                  @input="validateGrant"
                >
                <template #errors>
                  <CadenceValidationMessage v-for="error in grant_form.fields.valid_days.errors" :key="error">{{ error }}</CadenceValidationMessage>
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
                :class="['w-full textarea', grant_form.fields.approval_reason.errors.length > 0 && 'textarea-error']"
                @input="validateGrant"
              ></textarea>
              <template #errors>
                <CadenceValidationMessage v-for="error in grant_form.fields.approval_reason.errors" :key="error">{{ error }}</CadenceValidationMessage>
              </template>
            </CadenceField>

            <button :id="grant_form.submit.id" type="submit" class="btn btn-primary btn-sm w-full">
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
                :class="['w-full select', revocation_form.fields.automation_grant_id.errors.length > 0 && 'select-error']"
              >
                <option
                  v-for="option in revocation_form.fields.automation_grant_id.options"
                  :key="option.value"
                  :value="option.value"
                >{{ option.label }}</option>
              </select>
              <template #errors>
                <CadenceValidationMessage v-for="error in revocation_form.fields.automation_grant_id.errors" :key="error">{{ error }}</CadenceValidationMessage>
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
                :class="['w-full textarea', revocation_form.fields.reason.errors.length > 0 && 'textarea-error']"
              ></textarea>
              <template #errors>
                <CadenceValidationMessage v-for="error in revocation_form.fields.reason.errors" :key="error">{{ error }}</CadenceValidationMessage>
              </template>
            </CadenceField>

            <button :id="revocation_form.submit.id" type="submit" class="btn btn-error btn-sm w-full">
              {{ revocation_form.submit.label }}
            </button>
          </form>
        </CadenceDetailsFrame>
      </section>

      <p
        v-if="authorization.admin_required"
        class="border-l-2 border-warning px-3 text-xs text-warning"
      >
        {{ authorization.admin_required.copy }}
      </p>
    </aside>
  </div>
</template>
