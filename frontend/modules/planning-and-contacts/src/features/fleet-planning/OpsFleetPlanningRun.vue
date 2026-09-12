<script setup lang="ts">
import { computed, h, inject } from "vue";
import CadencePanel from "@cadence/ui/CadencePanel.vue";
import {
  FLEET_RUN_PORT,
  type OpsFleetPlanningRunProps,
  type RunQuery,
} from "./OpsFleetPlanningRun.contracts";
import { useFleetRun } from "./fleet-run-state";
import { fleetRunPage } from "./fleet-run";
const props = defineProps<OpsFleetPlanningRunProps>();
const {
  model,
  draft,
  pending,
  notice,
  uncertain,
  receipt,
  locked,
  withinHorizon,
  canContinue,
  canRepair,
  refresh,
  execute,
  connected,
} = useFleetRun(() => props.run, props.port ?? inject(FLEET_RUN_PORT, undefined));
const planning = computed(() =>
  model.value ? `/missions/${encodeURIComponent(model.value.context.mission_id)}/ops/planning` : "",
);
const planHref = (id: string, version: number) =>
  model.value
    ? `/missions/${encodeURIComponent(model.value.context.mission_id)}/ops/plans/${encodeURIComponent(id)}?version=${version}`
    : undefined;
const label = (v: string) => v.replaceAll("_", " ");
const Pager = (p: { kind: keyof RunQuery; page: number; more: boolean; label: string }) => {
  const current = model.value;
  if (!current) return null;
  return h(
    "nav",
    {
      class: "flex items-center justify-between gap-4 border-t border-base-300 p-4 text-sm",
      "aria-label": p.label,
    },
    [
      p.page > 1
        ? h(
            "a",
            {
              id: `fleet-run-${p.kind}-previous`,
              href: fleetRunPage(current, p.kind, p.page - 1),
              class: "text-primary",
            },
            "Previous",
          )
        : h("span"),
      h("span", { class: "text-xs text-base-content/60" }, `Page ${p.page}`),
      p.more
        ? h(
            "a",
            {
              id: `fleet-run-${p.kind}-next`,
              href: fleetRunPage(current, p.kind, p.page + 1),
              class: "text-primary",
            },
            "Next",
          )
        : h("span"),
    ],
  );
};
</script>
<template>
  <main v-if="model" id="ops-fleet-planning-run-page" class="space-y-6 p-4 md:p-6">
    <header class="space-y-3">
      <a id="fleet-run-back" :href="planning" class="text-sm text-primary">Fleet planning</a>
      <div class="flex flex-wrap items-start justify-between gap-4">
        <div class="min-w-0">
          <p class="text-xs uppercase tracking-widest text-base-content/60">
            Planning &amp; contacts
          </p>
          <h1 class="mt-1 text-2xl font-semibold">Fleet planning run</h1>
          <p class="mt-2 break-all font-mono text-xs text-base-content/60">{{ model.id }}</p>
        </div>
        <button
          id="fleet-run-refresh"
          class="btn btn-ghost btn-sm"
          :disabled="!!pending || !connected"
          @click="refresh()"
        >
          {{ pending === "read" ? "Refreshing…" : "Refresh evidence" }}
        </button>
      </div>
      <div class="flex flex-wrap items-center gap-3 text-sm">
        <span id="fleet-run-lifecycle" class="border border-base-300 px-2 py-1 font-medium">{{
          label(model.lifecycle_state)
        }}</span
        ><span class="text-base-content/65">Phase: {{ label(model.phase) }}</span
        ><span class="text-base-content/50"
          >{{ label(model.trigger_kind) }} · {{ model.algorithm.key }} v{{
            model.algorithm.version
          }}</span
        >
      </div>
      <p class="break-words font-mono text-xs text-base-content/65">
        {{ model.horizon_start }} → {{ model.horizon_end }} UTC
      </p>
      <a
        v-if="model.candidate"
        id="fleet-run-candidate"
        :href="planHref(model.candidate.id, model.candidate.version)"
        class="inline-block text-sm text-primary"
        >Review candidate Plan v{{ model.candidate.version }} ·
        {{ label(model.candidate.lifecycle_state) }}</a
      >
      <p v-if="model.source" class="text-sm text-base-content/60">
        Repair of
        <a
          id="fleet-run-source"
          :href="`${planning}/runs/${encodeURIComponent(model.source.run_id)}`"
          class="text-primary"
          >{{ model.source.run_id }}</a
        >
        ·
        <a :href="planHref(model.source.plan_id, model.source.plan_version)" class="text-primary"
          >source Plan v{{ model.source.plan_version }}</a
        >
      </p>
    </header>
    <p v-if="notice" id="fleet-run-notice" role="status" class="text-sm text-base-content/70">
      {{ notice }}
    </p>
    <section
      v-if="uncertain"
      id="fleet-run-uncertain"
      role="alert"
      class="space-y-2 border border-warning/40 p-4"
    >
      <h2 class="font-semibold text-warning">Action outcome is unconfirmed</h2>
      <p class="text-sm text-base-content/70">
        Further actions are paused. Read refresh does not repeat the action.
      </p>
      <a :href="planning" class="text-sm text-primary">Inspect the run directory</a>
    </section>
    <section v-if="receipt" id="fleet-run-receipt" class="space-y-2 border border-success/40 p-4">
      <h2 class="font-semibold">
        {{
          receipt.outcome === "continued"
            ? "Planning attempt completed"
            : "Queued repair run created"
        }}
      </h2>
      <p class="text-sm text-base-content/65">
        {{ label(receipt.lifecycleState) }} · {{ label(receipt.phase) }}
      </p>
      <a
        id="fleet-run-receipt-link"
        :href="`${planning}/runs/${encodeURIComponent(receipt.fleetPlanningRunId)}`"
        class="text-sm text-primary"
        >{{
          receipt.outcome === "continued" ? "Open resulting run evidence" : "Open repair run"
        }}</a
      >
    </section>
    <section
      v-if="model.failure"
      id="fleet-run-failure"
      role="alert"
      class="space-y-2 border border-error/40 p-4"
    >
      <h2 class="font-semibold text-error">Planning did not complete successfully</h2>
      <p class="font-mono text-sm">{{ model.failure.code ?? "Failure details unavailable" }}</p>
    </section>
    <section
      id="fleet-run-policy"
      class="grid gap-5 border border-base-300 bg-base-200/15 p-5 md:grid-cols-2"
    >
      <div class="space-y-2">
        <h2 class="font-semibold">Pinned policy v{{ model.policy.version }}</h2>
        <p class="break-all font-mono text-xs text-base-content/60">{{ model.policy.id }}</p>
        <p class="text-sm text-base-content/65">
          {{ model.policy.max_horizon_seconds }} second maximum horizon ·
          {{ model.policy.max_contacts ?? "Uncapped" }} contacts
        </p>
        <details>
          <summary class="cursor-pointer text-xs text-base-content/60">
            Policy and run fingerprints
          </summary>
          <p class="mt-2 break-all font-mono text-xs text-base-content/50">
            Policy: {{ model.policy.content_sha256 }}
          </p>
          <p class="mt-2 break-all font-mono text-xs text-base-content/50">
            Run: {{ model.evidence.sha256 }}
          </p>
        </details>
      </div>
      <div class="space-y-3">
        <h2 class="font-semibold">
          {{ model.can_continue ? "Continue this run" : "Run is terminal" }}
        </h2>
        <p class="text-sm text-base-content/65">
          {{
            model.can_continue
              ? "Continue from the reviewed phase using the pinned policy and Requirement versions. This can search providers, optimize opportunities and create a candidate Plan."
              : "Use the candidate Plan to review approvals and execution, or inspect the recorded failure and repair evidence."
          }}
        </p>
        <button
          v-if="model.can_continue"
          id="fleet-run-continue"
          class="btn btn-primary btn-sm"
          :disabled="!canContinue"
          @click="execute('continue')"
        >
          {{ pending === "continue" ? "Planning…" : "Continue planning" }}
        </button>
      </div>
    </section>
    <div class="grid gap-5 xl:grid-cols-2">
      <CadencePanel
        id="fleet-run-inputs"
        class="min-w-0 border border-base-300 bg-base-200/15"
        header-class="border-b border-base-300 p-4"
        ><template #header
          ><h2 class="font-semibold">Requirement inputs and coverage</h2>
          <p class="mt-1 text-xs text-base-content/60">
            {{ model.requirements.total }} pinned inputs
          </p></template
        >
        <p v-if="!model.requirements.entries.length" class="p-4 text-sm text-base-content/60">
          No inputs on this page.
        </p>
        <article
          v-for="row in model.requirements.entries"
          :id="`fleet-run-input-${encodeURIComponent(row.id)}`"
          :key="row.id"
          class="space-y-2 border-b border-base-300 p-4"
        >
          <a
            :href="`/missions/${encodeURIComponent(model.context.mission_id)}/ops/requirements/${encodeURIComponent(row.requirement_id)}?version=${row.version}`"
            class="break-all font-mono text-sm text-primary"
            >{{ row.requirement_id }} · v{{ row.version }}</a
          >
          <p class="text-sm text-base-content/70">
            {{ label(row.input_state) }} · coverage {{ label(row.result_state) }} ·
            {{ row.priority }}
          </p>
          <p class="break-all text-xs text-base-content/55">Spacecraft {{ row.spacecraft_id }}</p>
          <p class="break-words font-mono text-xs text-base-content/55">
            {{ row.earliest_start }} → {{ row.latest_end }}
          </p>
          <p v-if="row.planning_run_id" class="break-all font-mono text-xs text-base-content/55">
            Search {{ row.planning_run_id }}
          </p>
        </article>
        <Pager
          kind="requirements_page"
          :page="model.requirements.page"
          :more="model.requirements.more"
          label="Requirement input pages"
        />
      </CadencePanel>
      <CadencePanel
        id="fleet-run-decisions"
        class="min-w-0 border border-base-300 bg-base-200/15"
        header-class="border-b border-base-300 p-4"
        ><template #header
          ><h2 class="font-semibold">Optimizer decisions</h2>
          <p class="mt-1 text-xs text-base-content/60">
            Ranked evidence and opportunity windows
          </p></template
        >
        <p v-if="!model.decisions.entries.length" class="p-4 text-sm text-base-content/60">
          No decisions on this page.
        </p>
        <article
          v-for="row in model.decisions.entries"
          :id="`fleet-run-decision-${encodeURIComponent(row.id)}`"
          :key="row.id"
          class="space-y-2 border-b border-base-300 p-4"
        >
          <div class="flex flex-wrap items-center gap-3">
            <strong class="text-sm">{{ label(row.disposition) }}</strong
            ><span class="text-xs text-base-content/60"
              >Rank {{ row.rank ?? "—" }} · score {{ row.score }}</span
            >
          </div>
          <p class="break-all font-mono text-xs text-base-content/70">{{ row.snapshot_id }}</p>
          <p class="break-all text-xs text-base-content/55">Spacecraft {{ row.spacecraft_id }}</p>
          <p class="break-words font-mono text-xs text-base-content/60">
            {{ row.starts_at }} → {{ row.ends_at }}
          </p>
          <p v-if="row.rationale" class="text-sm text-base-content/65">{{ row.rationale }}</p>
          <p class="text-xs text-base-content/60">
            {{
              row.constraints_satisfied
                ? "Hard constraints satisfied"
                : "Hard constraints not satisfied"
            }}<span v-if="row.failures.length"> · {{ row.failures.join(", ") }}</span>
          </p>
        </article>
        <Pager
          kind="decisions_page"
          :page="model.decisions.page"
          :more="model.decisions.more"
          label="Optimizer decision pages"
        />
      </CadencePanel>
      <CadencePanel
        id="fleet-run-resources"
        class="min-w-0 border border-base-300 bg-base-200/15"
        header-class="border-b border-base-300 p-4"
        ><template #header><h2 class="font-semibold">Resource pressure</h2></template>
        <p v-if="!model.resources.entries.length" class="p-4 text-sm text-base-content/60">
          No resource summary on this page.
        </p>
        <article
          v-for="row in model.resources.entries"
          :id="`fleet-run-resource-${encodeURIComponent(row.key)}`"
          :key="row.key"
          class="space-y-2 border-b border-base-300 p-4"
        >
          <p class="break-all font-mono text-xs">{{ row.key }}</p>
          <p class="text-sm" :class="row.over_capacity ? 'text-warning' : 'text-base-content/65'">
            Peak {{ row.peak_parallel }} / capacity {{ row.capacity }} ·
            {{ row.selected_count }} selected
          </p>
        </article>
        <Pager
          kind="resources_page"
          :page="model.resources.page"
          :more="model.resources.more"
          label="Resource summary pages"
      /></CadencePanel>
      <CadencePanel
        id="fleet-run-automation"
        class="min-w-0 border border-base-300 bg-base-200/15"
        header-class="border-b border-base-300 p-4"
        ><template #header><h2 class="font-semibold">Automation history</h2></template>
        <p v-if="!model.automation.entries.length" class="p-4 text-sm text-base-content/60">
          No automation actions on this page.
        </p>
        <article
          v-for="row in model.automation.entries"
          :id="`fleet-run-automation-${encodeURIComponent(row.id)}`"
          :key="row.id"
          class="space-y-2 border-b border-base-300 p-4"
        >
          <p class="text-sm font-medium">
            {{ label(row.action) }} · {{ label(row.lifecycle_state) }} · attempt
            {{ row.attempt_count }}
          </p>
          <p class="break-all font-mono text-xs text-base-content/60">{{ row.id }}</p>
          <p class="break-all text-xs text-base-content/55">
            Grant {{ row.grant_id }} · service identity {{ row.service_identity_id }}
          </p>
          <a
            v-if="row.plan_id && row.plan_version"
            :href="planHref(row.plan_id, row.plan_version)"
            class="text-xs text-primary"
            >Review Plan v{{ row.plan_version }}</a
          >
        </article>
        <Pager
          kind="automation_page"
          :page="model.automation.page"
          :more="model.automation.more"
          label="Automation action pages"
      /></CadencePanel>
    </div>
    <section
      id="fleet-run-repair"
      class="space-y-4 border border-base-300 bg-base-200/15 p-3 sm:p-5"
    >
      <header class="space-y-2">
        <h2 class="text-lg font-semibold">Repair planning</h2>
        <p
          v-if="!model.repair.evidence"
          id="fleet-run-repair-unavailable"
          class="text-sm text-base-content/60"
        >
          Repair is unavailable: {{ label(model.repair.reason ?? "source unavailable") }}.
        </p>
      </header>
      <template v-if="model.repair.evidence && model.repair.policy && model.repair.commitments">
        <p class="text-sm text-base-content/65">
          Source Plan v{{ model.repair.evidence.plan_version }} · active repair policy v{{
            model.repair.policy.version
          }}
          · attempt {{ model.repair.attempt }} / {{ model.repair.policy.max_attempts }}
        </p>
        <p class="text-sm text-base-content/60">
          The successor keeps these reserved, uncertain, requesting or previously locked
          commitments. The source Plan is preserved.
        </p>
        <div id="fleet-run-commitments" class="divide-y divide-base-300 border border-base-300">
          <p
            v-if="!model.repair.commitments.entries.length"
            class="p-4 text-sm text-base-content/60"
          >
            No locked commitments on this page.
          </p>
          <article
            v-for="row in model.repair.commitments.entries"
            :id="`fleet-run-commitment-${encodeURIComponent(row.id)}`"
            :key="row.id"
            class="space-y-2 p-4"
          >
            <p class="break-all font-mono text-xs">{{ row.id }}</p>
            <p class="break-all text-xs text-base-content/60">Spacecraft {{ row.spacecraft_id }}</p>
            <p class="break-words font-mono text-xs text-base-content/55">
              {{ row.starts_at }} → {{ row.ends_at }}
            </p>
          </article>
          <Pager
            kind="commitments_page"
            :page="model.repair.commitments.page"
            :more="model.repair.commitments.more"
            label="Locked commitment pages"
          />
        </div>
        <p v-if="!model.repair.available" class="text-sm text-warning">
          {{ label(model.repair.reason ?? "repair unavailable") }}
        </p>
        <form
          v-else
          id="fleet-run-repair-form"
          class="space-y-4"
          @submit.prevent="execute('repair')"
        >
          <div class="grid gap-4 sm:grid-cols-2">
            <label class="min-w-0 space-y-2 text-sm" for="fleet-run-repair-start"
              ><span class="block text-base-content/65">Repair horizon start (UTC)</span
              ><input
                id="fleet-run-repair-start"
                v-model="draft.horizon_start"
                name="repair[horizon_start]"
                type="datetime-local"
                step="1"
                required
                class="input min-w-0 w-full max-w-full text-xs sm:text-sm"
                :disabled="locked" /></label
            ><label class="min-w-0 space-y-2 text-sm" for="fleet-run-repair-end"
              ><span class="block text-base-content/65">Repair horizon end (UTC)</span
              ><input
                id="fleet-run-repair-end"
                v-model="draft.horizon_end"
                name="repair[horizon_end]"
                type="datetime-local"
                step="1"
                required
                class="input min-w-0 w-full max-w-full text-xs sm:text-sm"
                :disabled="locked"
            /></label>
          </div>
          <p class="text-xs text-base-content/60">
            Maximum repair horizon: {{ model.repair.policy.max_repair_horizon_seconds }} seconds.
          </p>
          <p v-if="!withinHorizon" class="text-sm text-warning">
            Choose an increasing UTC window within the approved repair horizon.
          </p>
          <button
            id="fleet-run-repair-submit"
            class="btn btn-primary btn-sm"
            :disabled="!canRepair"
          >
            {{ pending === "repair" ? "Creating repair…" : "Create queued repair run" }}
          </button>
        </form>
      </template>
    </section>
  </main>
  <section v-else id="fleet-run-unavailable" role="alert" class="space-y-3 p-6">
    <h1 class="text-xl font-semibold">Fleet run unavailable</h1>
    <p class="text-sm text-base-content/60">The run evidence could not be verified.</p>
    <button
      v-if="connected"
      id="fleet-run-retry"
      class="btn btn-ghost btn-sm"
      :disabled="!!pending"
      @click="refresh()"
    >
      Retry read
    </button>
    <p v-if="notice" role="status">{{ notice }}</p>
  </section>
</template>
