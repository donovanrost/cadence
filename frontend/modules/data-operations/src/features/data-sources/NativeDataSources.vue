<script setup lang="ts">
import { computed } from "vue";
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import CadenceField from "@cadence/ui/CadenceField.vue";
import type { OpsPagePort, OpsPageReadPort } from "@cadence/plugin-sdk/ops-pages";
import {
  same,
  registrationFields,
  type SourcePage,
  type SourceDecisionAction,
  type DeploymentAction,
  type Job,
} from "./native-contract";
import { useDataSources } from "./native-state";
import SourcePageControls from "./SourcePageControls.vue";
import SourceEvidence from "./SourceEvidence.vue";
defineOptions({ inheritAttrs: false });
const props = defineProps<{ page: SourcePage; port: OpsPagePort; readPort: OpsPageReadPort }>();
const state = useDataSources(() => props.page, props.port, props.readPort);
const {
  page: currentPage,
  draft,
  reviewedSource,
  targetSource,
  selectedBinding,
  lastEffect,
  pending,
  locked,
  disabled,
  notice,
} = state;
const model = computed(() => currentPage.value.model),
  selected = computed(() => model.value.selected);
const receipt = computed(() =>
  lastEffect.value?.status === "completed" ? lastEffect.value.result : null,
);
const recordedJob = computed(() => {
  const result = receipt.value?.result;
  if (!result) return null;
  return "jobId" in result ? result : "job" in result ? result.job : null;
});
const recordedBinding = computed(() => {
  const op = lastEffect.value;
  return op?.action === "change-binding" && op.status === "completed" ? op.result.result : null;
});
const base = `/missions/${encodeURIComponent(props.page.model.context.mission_id)}/ops/data-sources`;
const href = (id: string, settings = false) =>
  `${base}/${encodeURIComponent(id)}${settings ? "/settings" : ""}`;
const manage = computed(
  () =>
    model.value.mode === "settings" &&
    model.value.permissions.manage &&
    !!selected.value?.source.editable,
);
const sourceChanged = computed(
  () => selected.value?.source.evidence !== reviewedSource.value?.evidence,
);
const decisionDisabled = computed(() => disabled.value || sourceChanged.value || !manage.value);
const repeated = computed(
  () =>
    lastEffect.value?.action === "register-source" &&
    lastEffect.value.status === "completed" &&
    lastEffect.value.input.params.source.data_source_id.trim() === draft.data_source_id.trim(),
);
const currentBinding = computed(() =>
  model.value.bindings.entries.find((b) => b.id === selectedBinding.value?.id),
);
const currentTarget = computed(() =>
  model.value.sources.entries.find((s) => s.id === targetSource.value?.id),
);
const bindingReady = computed(
  () =>
    !!selectedBinding.value &&
    !!targetSource.value &&
    currentBinding.value?.evidence === selectedBinding.value.evidence &&
    currentTarget.value?.evidence === targetSource.value.evidence &&
    currentTarget.value?.status === "active" &&
    selectedBinding.value.editable &&
    targetSource.value.logical_source === selectedBinding.value.logical_source,
);
const fields: Record<(typeof registrationFields)[number], string> = {
  data_source_id: "Source identity",
  logical_source: "Logical source",
  kind: "Backend kind",
  isolation_level: "Isolation",
  credentials_ref: "Credential reference",
  credential_provider: "Credential provider",
  endpoint_ref: "Endpoint reference",
  material_env_profile: "Credential environment profile",
  http_endpoint_env: "HTTP endpoint environment variable",
  storage: "Storage",
};
const options: Record<string, string[]> = {
  kind: ["managed_tsdb", "byo_tsdb"],
  isolation_level: ["shared", "org_isolated", "mission_isolated", "customer_owned"],
  storage: ["questdb", "postgres_projection"],
};
const actions: [SourceDecisionAction, string][] = [
  ["probe-source", "Probe source"],
  ["provision-tsdb-backend", "Provision backend"],
  ["reconcile-tsdb-backend", "Reconcile backend"],
  ["deprovision-tsdb-backend", "Deprovision backend"],
];
const dedicatedBackend = computed(
  () =>
    selected.value?.source.kind === "byo_tsdb" &&
    ["org_isolated", "mission_isolated"].includes(selected.value.source.isolation),
);
const visibleActions = computed(() =>
  actions.filter(([action]) => action === "probe-source" || dedicatedBackend.value),
);
function register(action: "register-source" | "validate-registration") {
  if (disabled.value || repeated.value || !draft.data_source_id.trim()) return;
  if (
    action === "register-source" &&
    !window.confirm(`Register data source ${draft.data_source_id.trim()}?`)
  )
    return;
  return state.execute(action, {
    params: { source: { ...draft } },
    review: {},
    confirmed: action === "register-source",
  });
}
function decide(
  ...args:
    | [action: SourceDecisionAction]
    | [action: "rotate-source-credential", extra: { "credentials-ref": string }]
) {
  const [action] = args;
  const source = reviewedSource.value;
  if (
    !source ||
    decisionDisabled.value ||
    !window.confirm(`Apply ${action.replaceAll("-", " ")} to source ${source.id}?`)
  )
    return;
  const review = { source: source.evidence };
  if (args[0] === "rotate-source-credential")
    return state.execute(args[0], {
      params: { "data-source-id": source.id, ...args[1] },
      review,
      confirmed: true,
    });
  return state.execute(args[0], {
    params: { "data-source-id": source.id },
    review,
    confirmed: true,
  });
}
function changeBinding() {
  const b = selectedBinding.value,
    target = targetSource.value,
    source = reviewedSource.value;
  if (
    !b ||
    !target ||
    !source ||
    decisionDisabled.value ||
    !bindingReady.value ||
    !window.confirm(`Move binding ${b.id} from ${source.id} to ${target.id}?`)
  )
    return;
  return state.execute("change-binding", {
    params: { binding: { binding_id: b.id, data_source_id: target.id } },
    review: { source: source.evidence, binding: b.evidence, target_source: target.evidence },
    confirmed: true,
  });
}
function deployment(action: DeploymentAction, job: Job) {
  const source = reviewedSource.value;
  if (
    !source ||
    decisionDisabled.value ||
    !window.confirm(
      `Apply ${action.replaceAll("-", " ")} to job ${job.id} for source ${source.id}?`,
    )
  )
    return;
  return state.execute(action, {
    params: { "job-id": job.id },
    review: { source: source.evidence, job: job.evidence },
    confirmed: true,
  });
}
function chooseBinding(event: Event) {
  if (!(event.currentTarget instanceof HTMLSelectElement)) return;
  const value = event.currentTarget.value;
  const b = model.value.bindings.entries.find((b) => b.id === value);
  state.selectBinding(b ?? null);
}
function chooseTarget(event: Event) {
  if (!(event.currentTarget instanceof HTMLSelectElement)) return;
  const value = event.currentTarget.value;
  const s = model.value.sources.entries.find((s) => s.id === value);
  state.selectTarget(s ?? null);
}
</script>
<template>
  <main id="ops-data-sources-page" class="min-w-0 space-y-5">
    <CadencePageHeading>
      <template #title>Data Sources</template>
      <template #eyebrow>System / Source operations</template>
      <template #description
        >Inspect source configuration, binding history and observed telemetry before changing a
        backend.</template
      >
      <template #actions>
        <nav aria-label="Data Sources navigation" class="flex flex-wrap gap-2">
          <a :href="base" class="btn btn-sm btn-outline" @click.prevent="port.navigate(base)"
            >Source directory</a
          >
          <a
            v-if="model.permissions.manage && model.mode !== 'registration'"
            id="sources-registration"
            :href="base + '/registration/new'"
            class="btn btn-sm btn-outline"
            @click.prevent="port.navigate(base + '/registration/new')"
            >Register source</a
          >
          <button
            id="sources-refresh"
            type="button"
            class="btn btn-sm btn-outline"
            :disabled="pending"
            @click="state.refresh()"
          >
            Refresh evidence
          </button>
        </nav>
      </template>
    </CadencePageHeading>
    <p v-if="notice" id="sources-notice" role="status" class="border border-base-300 p-3 text-sm">
      {{ notice }}
    </p>
    <p
      v-if="locked"
      id="sources-unconfirmed"
      role="alert"
      class="border border-warning p-3 text-sm"
    >
      The last outcome is unconfirmed. Refresh to recover the response before submitting another
      operation.
    </p>
    <section
      v-if="lastEffect"
      id="sources-operation"
      aria-label="Last source operation"
      class="space-y-2 border border-base-300 bg-base-100 p-4 text-sm"
    >
      <p>
        <strong>{{
          lastEffect.status === "completed"
            ? "Operation recorded"
            : lastEffect.status === "rejected"
              ? "Operation not accepted"
              : "Outcome unconfirmed"
        }}</strong>
      </p>
      <p class="break-all font-mono text-xs">
        Operation {{ lastEffect.id }} · {{ lastEffect.action }}
      </p>
      <p v-for="feedback in lastEffect.feedback" :key="feedback">
        {{ feedback.replaceAll("_", " ") }}
      </p>
      <template v-if="lastEffect.result?.source_id">
        <a
          :href="href(lastEffect.result.source_id)"
          target="_blank"
          rel="noopener"
          class="link break-all"
          >Inspect source {{ lastEffect.result.source_id }}</a
        >
        <ul aria-label="Recorded event identities" class="space-y-1 font-mono text-xs">
          <li v-for="id in receipt?.event_ids ?? []" :key="id" class="break-all">
            {{ id }}
          </li>
        </ul>
        <p v-if="recordedJob" class="break-all font-mono text-xs">
          Job {{ recordedJob.jobId }} · run
          {{ recordedJob.runId }}
        </p>
        <p v-if="recordedBinding" class="break-all font-mono text-xs">
          Binding {{ recordedBinding.bindingId }} · version {{ recordedBinding.bindingVersion }} ·
          destination
          {{ recordedBinding.dataSourceId }}
        </p>
      </template>
    </section>
    <section
      v-if="model.mode === 'registration'"
      class="space-y-4 border border-base-300 bg-base-100 p-4"
      aria-label="Register data source"
    >
      <h2 class="text-sm font-semibold">Register a source</h2>
      <p class="text-sm text-base-content/60">
        Use credential and environment references to configure access. Registration records the
        source; backend provisioning is a separate operation.
      </p>
      <form
        id="source-registration-form"
        class="space-y-4"
        @submit.prevent="register('register-source')"
      >
        <div class="grid min-w-0 gap-4 md:grid-cols-2">
          <CadenceField
            v-for="field in registrationFields"
            :key="field"
            :label="fields[field]"
            :control-id="'source-' + field"
          >
            <select
              v-if="field === 'logical_source' || options[field]"
              :id="'source-' + field"
              v-model="draft[field]"
              class="select select-bordered w-full"
              :disabled="pending || locked"
            >
              <option
                v-for="option in field === 'logical_source' ? model.adapters : options[field]"
                :key="option"
                :value="option"
              >
                {{ option.replaceAll("_", " ") }}
              </option>
            </select>
            <input
              v-else
              :id="'source-' + field"
              v-model="draft[field]"
              class="input input-bordered w-full font-mono"
              :required="
                field === 'data_source_id' ||
                (field === 'credentials_ref' && draft.kind === 'byo_tsdb')
              "
              :maxlength="field === 'endpoint_ref' ? 2048 : 240"
              :disabled="pending || locked"
            />
          </CadenceField>
        </div>
        <div class="flex flex-wrap gap-2">
          <button
            id="source-validate"
            type="button"
            class="btn btn-sm btn-outline"
            :disabled="disabled || repeated || !draft.data_source_id.trim()"
            @click="register('validate-registration')"
          >
            Validate configuration
          </button>
          <button
            id="source-register"
            type="submit"
            class="btn btn-sm btn-primary"
            :disabled="disabled || repeated || !draft.data_source_id.trim()"
          >
            Register source
          </button>
        </div>
        <p v-if="repeated" class="text-sm text-base-content/60">
          This source was registered. Inspect its returned identity before starting another
          registration.
        </p>
      </form>
    </section>
    <div class="grid min-w-0 gap-5 xl:grid-cols-[18rem_minmax(0,1fr)]">
      <aside
        id="source-directory"
        class="min-w-0 self-start border border-base-300 bg-base-100 p-4"
      >
        <h2 class="mb-3 text-sm font-semibold">Sources</h2>
        <p v-if="!model.sources.entries.length" class="text-sm text-base-content/60">
          No sources on this page.
        </p>
        <ul class="space-y-2">
          <li
            v-for="source in model.sources.entries"
            :key="source.id"
            class="space-y-1 border border-base-300 p-3 text-xs"
          >
            <a
              :href="href(source.id)"
              class="link break-all font-mono"
              @click.prevent="port.navigate(href(source.id))"
              >{{ source.id }}</a
            >
            <p>{{ source.status }} · {{ source.logical_source ?? "Adapter not identified" }}</p>
            <p>{{ source.editable ? "Mission definition" : "Shared definition" }}</p>
          </li>
        </ul>
        <SourcePageControls
          id="sources-page"
          label="Sources"
          :page="model.sources"
          :disabled="pending || locked"
          @change="state.chooseQuery({ page: String($event) })"
        />
      </aside>
      <div class="min-w-0 space-y-5">
        <section
          v-if="selected"
          id="source-detail"
          class="min-w-0 space-y-4 border border-base-300 bg-base-100 p-4"
        >
          <header class="space-y-2">
            <h2 class="break-all font-mono text-sm font-semibold">{{ selected.source.id }}</h2>
            <p class="text-sm">
              {{ selected.source.status }} · {{ selected.source.kind }} ·
              {{ selected.source.isolation }}
            </p>
            <a
              v-if="
                model.mode !== 'settings' && model.permissions.manage && selected.source.editable
              "
              id="source-settings"
              :href="href(selected.source.id, true)"
              class="link text-sm"
              @click.prevent="port.navigate(href(selected.source.id, true))"
              >Manage source</a
            >
          </header>
          <dl class="grid min-w-0 gap-3 text-xs sm:grid-cols-2">
            <div>
              <dt class="text-base-content/60">Owner</dt>
              <dd>{{ selected.source.owner }}</dd>
            </div>
            <div>
              <dt class="text-base-content/60">Logical source</dt>
              <dd>{{ selected.source.logical_source ?? "Not recorded" }}</dd>
            </div>
            <div>
              <dt class="text-base-content/60">Credential reference</dt>
              <dd class="break-all font-mono">
                {{ selected.source.credential_reference ?? "None" }}
              </dd>
            </div>
            <div>
              <dt class="text-base-content/60">Current source event</dt>
              <dd class="break-all font-mono">{{ selected.source.event_id ?? "Not recorded" }}</dd>
            </div>
            <div>
              <dt class="text-base-content/60">Backend lifecycle</dt>
              <dd>
                {{ selected.source.backend.status ?? "Not recorded" }} ·
                {{ selected.source.backend.operation ?? "No operation recorded" }}
              </dd>
            </div>
          </dl>
          <ul class="flex flex-wrap gap-2 text-xs">
            <li
              v-for="capability in selected.source.capabilities"
              :key="capability.name"
              class="border border-base-300 px-2 py-1"
            >
              {{ capability.name }}: {{ capability.enabled ? "Enabled" : "Disabled" }}
            </li>
          </ul>
          <p v-if="selected.source.capabilities_more" class="text-xs">
            Showing the first 25 capability flags.
          </p>
          <p v-if="!selected.source.editable" class="text-sm text-base-content/60">
            This shared definition cannot be changed from this mission.
          </p>
          <div v-if="manage" id="source-controls" class="space-y-3 border-t border-base-300 pt-4">
            <div v-if="sourceChanged" role="status" class="space-y-2 text-sm">
              <p>The source changed since your review. Your binding selection is retained.</p>
              <button
                id="source-accept-review"
                type="button"
                class="btn btn-sm btn-outline"
                :disabled="disabled"
                @click="state.acceptSource()"
              >
                Use current source evidence
              </button>
            </div>
            <div class="flex flex-wrap gap-2">
              <button
                id="source-disable"
                type="button"
                class="btn btn-sm btn-outline"
                :disabled="decisionDisabled || selected.source.status !== 'active'"
                @click="decide('disable-source')"
              >
                Disable source
              </button>
              <button
                id="source-enable"
                type="button"
                class="btn btn-sm btn-outline"
                :disabled="decisionDisabled || selected.source.status !== 'disabled'"
                @click="decide('enable-source')"
              >
                Enable source
              </button>
              <button
                v-for="[action, label] in visibleActions"
                :id="'source-' + action"
                :key="action"
                type="button"
                class="btn btn-sm btn-outline"
                :disabled="decisionDisabled"
                @click="decide(action)"
              >
                {{ label }}
              </button>
              <button
                v-if="selected.source.credential_reference"
                id="source-rotate"
                type="button"
                class="btn btn-sm btn-outline"
                :disabled="decisionDisabled"
                @click="
                  decide('rotate-source-credential', {
                    'credentials-ref': selected.source.credential_reference,
                  })
                "
              >
                Rotate credential reference
              </button>
            </div>
          </div>
        </section>
        <section
          aria-label="Bindings"
          class="min-w-0 space-y-3 border border-base-300 bg-base-100 p-4"
        >
          <h2 class="text-sm font-semibold">
            {{ selected ? "Source bindings" : "Visible bindings" }}
          </h2>
          <p v-if="!model.bindings.entries.length" class="text-sm text-base-content/60">
            No bindings on this page.
          </p>
          <ul class="space-y-2">
            <li
              v-for="binding in model.bindings.entries"
              :key="binding.id"
              class="space-y-1 border border-base-300 p-3 text-xs"
            >
              <p class="break-all font-mono">{{ binding.id }} · source {{ binding.source_id }}</p>
              <p>
                {{ binding.logical_source }} · {{ binding.realm }} · dataset
                {{ binding.dataset ?? "Default" }} · priority {{ binding.priority }}
              </p>
              <p>{{ binding.status }} · version {{ binding.version }}</p>
              <button
                v-if="selected"
                :id="'source-binding-history-' + binding.id"
                type="button"
                class="link"
                :disabled="pending || locked"
                @click="state.chooseQuery({ binding_id: binding.id, binding_events_page: '1' })"
              >
                Inspect binding history
              </button>
            </li>
          </ul>
          <SourcePageControls
            id="sources-bindings_page"
            label="Bindings"
            :page="model.bindings"
            :disabled="pending || locked"
            @change="state.chooseQuery({ bindings_page: String($event) })"
          />
          <form
            v-if="manage"
            id="source-binding-form"
            class="space-y-3 border-t border-base-300 pt-4"
            @submit.prevent="changeBinding()"
          >
            <h3 class="text-sm font-semibold">Change a binding destination</h3>
            <CadenceField label="Reviewed binding" control-id="source-binding"
              ><select
                id="source-binding"
                :value="selectedBinding?.id ?? ''"
                class="select select-bordered w-full"
                :disabled="pending || locked"
                @change="chooseBinding"
              >
                <option value="">Select a binding from this page</option>
                <option v-if="selectedBinding && !currentBinding" :value="selectedBinding.id">
                  {{ selectedBinding.id }} · retained review, off page
                </option>
                <option
                  v-for="binding in model.bindings.entries.filter((b) => b.editable)"
                  :key="binding.id"
                  :value="binding.id"
                >
                  {{ binding.id }} · version {{ binding.version }}
                </option>
              </select></CadenceField
            >
            <CadenceField label="Destination source" control-id="source-target"
              ><select
                id="source-target"
                :value="targetSource?.id ?? ''"
                class="select select-bordered w-full"
                :disabled="pending || locked"
                @change="chooseTarget"
              >
                <option value="">Select a source from the directory page</option>
                <option v-if="targetSource && !currentTarget" :value="targetSource.id">
                  {{ targetSource.id }} · retained review, off page
                </option>
                <option
                  v-for="source in model.sources.entries.filter((s) => s.status === 'active')"
                  :key="source.id"
                  :value="source.id"
                >
                  {{ source.id }} · {{ source.logical_source }}
                </option>
              </select></CadenceField
            >
            <p v-if="selectedBinding || targetSource" class="text-xs text-base-content/60">
              Both reviewed records must be on their current pages and use the same logical source.
            </p>
            <button
              v-if="currentBinding && selectedBinding && !same(currentBinding, selectedBinding)"
              id="source-accept-binding"
              type="button"
              class="btn btn-sm btn-outline"
              :disabled="disabled"
              @click="state.selectBinding(currentBinding)"
            >
              Use current binding evidence
            </button>
            <button
              v-if="currentTarget && targetSource && !same(currentTarget, targetSource)"
              id="source-accept-target"
              type="button"
              class="btn btn-sm btn-outline"
              :disabled="disabled"
              @click="state.selectTarget(currentTarget)"
            >
              Use current destination evidence
            </button>
            <button
              id="source-change-binding"
              type="submit"
              class="btn btn-sm btn-primary"
              :disabled="decisionDisabled || !bindingReady"
            >
              Change binding
            </button>
          </form>
        </section>
        <SourceEvidence
          v-if="selected"
          :selected="selected"
          :disabled="pending || locked"
          :manage="manage && !decisionDisabled"
          @page="(key, value) => state.chooseQuery({ [key]: String(value) })"
          @job="deployment"
        />
      </div>
    </div>
  </main>
</template>
