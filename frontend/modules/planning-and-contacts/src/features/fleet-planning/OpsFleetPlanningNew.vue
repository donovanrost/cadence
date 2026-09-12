<script setup lang="ts">
import { computed, inject } from "vue";
import CadencePanel from "@cadence/ui/CadencePanel.vue";
import { FLEET_START_PORT, type OpsFleetPlanningNewProps } from "./OpsFleetPlanningNew.contracts";
import { useFleetStart } from "./fleet-start-state";
const props = defineProps<OpsFleetPlanningNewProps>();
const {
  model,
  draft,
  pending,
  notice,
  review,
  receipt,
  uncertain,
  locked,
  canPreview,
  canCreate,
  withinHorizon,
  preview,
  create,
  refresh,
  connected,
} = useFleetStart(() => props.start, props.port ?? inject(FLEET_START_PORT, undefined));
const base = computed(() =>
  model.value ? `/missions/${encodeURIComponent(model.value.context.mission_id)}/ops/planning` : "",
);
const label = (v: string) => v.replaceAll("_", " ");
</script>
<template>
  <main v-if="model" id="ops-fleet-planning-new-page" class="space-y-6 p-4 md:p-6">
    <header class="space-y-3">
      <a id="fleet-start-back" :href="base" class="text-sm text-primary">Fleet planning</a>
      <div class="flex flex-wrap items-start justify-between gap-4">
        <div>
          <p class="text-xs uppercase tracking-widest text-base-content/60">
            Planning &amp; contacts
          </p>
          <h1 class="mt-1 text-2xl font-semibold">Plan a fleet horizon</h1>
          <p class="mt-2 max-w-2xl text-sm text-base-content/60">
            Review the approved policy and exact demand inputs before creating a queued planning
            run.
          </p>
        </div>
        <button
          id="fleet-start-refresh"
          class="btn btn-ghost btn-sm"
          :disabled="!!pending || !connected"
          @click="refresh()"
        >
          {{ pending === "read" ? "Refreshing…" : "Refresh policy" }}
        </button>
      </div>
    </header>
    <p v-if="notice" id="fleet-start-notice" role="status" class="text-sm text-base-content/70">
      {{ notice }}
    </p>
    <section
      v-if="uncertain"
      id="fleet-start-uncertain"
      role="alert"
      class="space-y-2 border border-warning/40 p-4"
    >
      <h2 class="font-semibold text-warning">Creation outcome is unconfirmed</h2>
      <p class="text-sm text-base-content/70">
        Further creation is paused. Check the run directory for this horizon before starting another
        run.
      </p>
      <a :href="base" class="inline-block text-sm text-primary">Open run directory</a>
    </section>
    <section v-if="receipt" id="fleet-start-receipt" class="space-y-2 border border-success/40 p-4">
      <h2 class="font-semibold">Queued run created</h2>
      <p class="break-all font-mono text-sm">{{ receipt.fleetPlanningRunId }}</p>
      <p class="text-sm text-base-content/65">
        {{ receipt.requirementCount }} exact Requirement versions are attached. Provider searching
        begins when you continue the run.
      </p>
      <a
        id="fleet-start-open-run"
        :href="`${base}/runs/${encodeURIComponent(receipt.fleetPlanningRunId)}`"
        class="btn btn-primary btn-sm"
        >Open run</a
      >
    </section>
    <section
      v-if="!model.policy"
      id="fleet-start-policy-required"
      class="space-y-3 border border-warning/35 p-5"
    >
      <h2 class="font-semibold">An approved fleet policy is required</h2>
      <p class="text-sm text-base-content/65">
        An administrator must approve the scheduling boundary before you can review a new horizon.
      </p>
      <a id="fleet-start-policy-link" :href="`${base}/policy`" class="text-sm text-primary"
        >Review policy</a
      >
    </section>
    <div v-else class="grid gap-5 xl:grid-cols-[minmax(0,1fr)_20rem]">
      <CadencePanel
        header-class=""
        class="min-w-0 border border-base-300 bg-base-200/15 p-3 sm:p-5"
      >
        <form id="fleet-start-form" class="space-y-5" @submit.prevent="preview()">
          <div class="grid gap-4 sm:grid-cols-2">
            <label for="fleet-start-horizon-start" class="min-w-0 space-y-2 text-sm"
              ><span class="block text-base-content/65">Horizon start (UTC)</span
              ><input
                id="fleet-start-horizon-start"
                v-model="draft.horizon_start"
                name="fleet_run[horizon_start]"
                type="datetime-local"
                step="1"
                required
                class="input min-w-0 w-full max-w-full text-xs sm:text-sm"
                :disabled="locked"
            /></label>
            <label for="fleet-start-horizon-end" class="min-w-0 space-y-2 text-sm"
              ><span class="block text-base-content/65">Horizon end (UTC)</span
              ><input
                id="fleet-start-horizon-end"
                v-model="draft.horizon_end"
                name="fleet_run[horizon_end]"
                type="datetime-local"
                step="1"
                required
                class="input min-w-0 w-full max-w-full text-xs sm:text-sm"
                :disabled="locked"
            /></label>
          </div>
          <label for="fleet-start-recurring" class="flex items-start gap-3 text-sm"
            ><input
              id="fleet-start-recurring"
              v-model="draft.include_recurring"
              name="fleet_run[include_recurring]"
              type="checkbox"
              class="checkbox checkbox-sm mt-0.5"
              :disabled="locked"
            /><span
              ><span class="block font-medium">Include recurring demand</span
              ><span class="mt-1 block text-base-content/60"
                >Review active template versions and their catch-up bounds. Creation materializes
                their due occurrences together with the run.</span
              ></span
            ></label
          >
          <p v-if="!withinHorizon" id="fleet-start-window-error" class="text-sm text-warning">
            Choose an increasing UTC window within the approved maximum of
            {{ model.policy.max_horizon_seconds }} seconds.
          </p>
          <button
            id="fleet-start-preview"
            type="submit"
            class="btn btn-primary btn-sm"
            :disabled="!canPreview"
          >
            {{ pending === "preview" ? "Reviewing…" : "Review inputs" }}
          </button>
        </form>
      </CadencePanel>
      <aside id="fleet-start-policy" class="space-y-3 border border-base-300 bg-base-200/15 p-5">
        <h2 class="font-semibold">Approved policy v{{ model.policy.version }}</h2>
        <p class="break-all font-mono text-xs text-base-content/60">{{ model.policy.id }}</p>
        <dl class="space-y-2 text-sm">
          <div>
            <dt class="text-base-content/55">Maximum horizon</dt>
            <dd>{{ model.policy.max_horizon_seconds }} seconds</dd>
          </div>
          <div>
            <dt class="text-base-content/55">Contact limit</dt>
            <dd>{{ model.policy.max_contacts ?? "Not capped by contact count" }}</dd>
          </div>
          <div>
            <dt class="text-base-content/55">Cost limit</dt>
            <dd>
              {{
                model.policy.max_estimated_cost_micros === null
                  ? "Not capped by estimated cost"
                  : `${model.policy.max_estimated_cost_micros} millionths of ${model.policy.currency}`
              }}
            </dd>
          </div>
          <div>
            <dt class="text-base-content/55">Search concurrency</dt>
            <dd>
              {{ model.policy.requirement_concurrency }} Requirements ·
              {{ model.policy.provider_search_concurrency }} provider searches
            </dd>
          </div>
        </dl>
        <details>
          <summary class="cursor-pointer text-xs text-base-content/60">Policy fingerprint</summary>
          <p class="mt-2 break-all font-mono text-xs text-base-content/50">
            {{ model.policy.content_sha256 }}
          </p>
        </details>
        <a :href="`${base}/policy`" class="inline-block text-sm text-primary"
          >Policy administration</a
        >
      </aside>
    </div>
    <section v-if="review" id="fleet-start-review" class="space-y-5">
      <header class="space-y-2">
        <h2 class="text-xl font-semibold">Review this horizon</h2>
        <p class="break-words font-mono text-xs text-base-content/65">
          {{ review.window.horizon_start }} → {{ review.window.horizon_end }} UTC
        </p>
        <p class="text-sm text-base-content/65">
          {{ review.requirements.total }} active Requirements ·
          {{ review.templates.total }} recurring templates · {{ review.occurrence_count }} due
          occurrences
        </p>
        <p class="text-sm text-base-content/55">
          {{ review.eligible_occurrence_count }} new occurrence windows overlap the horizon.
          Existing generated Requirements keep their current lifecycle and version.
        </p>
      </header>
      <div class="grid gap-5 xl:grid-cols-2">
        <CadencePanel
          id="fleet-start-requirements"
          class="min-w-0 border border-base-300 bg-base-200/15"
          header-class="border-b border-base-300 p-4"
        >
          <template #header><h3 class="font-semibold">Existing Requirement inputs</h3></template>
          <p v-if="!review.requirements.entries.length" class="p-4 text-sm text-base-content/60">
            No Requirements on this review page.
          </p>
          <div
            v-for="row in review.requirements.entries"
            :id="`fleet-start-requirement-${encodeURIComponent(row.id)}`"
            :key="row.id"
            class="space-y-2 border-b border-base-300 p-4"
          >
            <a
              :href="`/missions/${encodeURIComponent(review.context.mission_id)}/ops/requirements/${encodeURIComponent(row.id)}?version=${row.version}`"
              class="break-all font-mono text-sm text-primary"
              >{{ row.id }} · v{{ row.version }}</a
            >
            <p class="text-xs text-base-content/65">
              {{ row.priority }} · {{ label(row.success_measure) }}
            </p>
            <p class="break-all text-xs text-base-content/50">Spacecraft {{ row.spacecraft_id }}</p>
            <p class="break-words font-mono text-xs text-base-content/60">
              {{ row.earliest_start }} → {{ row.latest_end }}
            </p>
          </div>
          <nav
            aria-label="Requirement review pages"
            class="flex flex-wrap items-center justify-between gap-2 p-4 text-sm"
          >
            <button
              v-if="review.requirements.page > 1"
              id="fleet-start-requirements-previous"
              :disabled="locked"
              class="text-primary"
              @click="preview(review.requirements.page - 1, review.templates.page)"
            >
              Previous</button
            ><span class="text-xs text-base-content/60">Page {{ review.requirements.page }}</span
            ><button
              v-if="review.requirements.more"
              id="fleet-start-requirements-next"
              :disabled="locked"
              class="text-primary"
              @click="preview(review.requirements.page + 1, review.templates.page)"
            >
              Next
            </button>
          </nav>
        </CadencePanel>
        <CadencePanel
          id="fleet-start-templates"
          class="min-w-0 border border-base-300 bg-base-200/15"
          header-class="border-b border-base-300 p-4"
        >
          <template #header><h3 class="font-semibold">Recurring template inputs</h3></template>
          <p v-if="!review.templates.entries.length" class="p-4 text-sm text-base-content/60">
            {{
              review.window.include_recurring
                ? "No templates on this review page."
                : "Recurring materialization is excluded."
            }}
          </p>
          <div
            v-for="row in review.templates.entries"
            :id="`fleet-start-template-${encodeURIComponent(row.id)}`"
            :key="row.id"
            class="space-y-2 border-b border-base-300 p-4"
          >
            <p class="break-all font-mono text-sm">{{ row.id }} · v{{ row.version }}</p>
            <p class="text-xs text-base-content/65">
              {{ row.occurrence_count }} due occurrences · cap {{ row.maximum_occurrences }}
            </p>
            <p class="break-all text-xs text-base-content/50">Spacecraft {{ row.spacecraft_id }}</p>
            <p class="text-xs text-base-content/60">
              Maximum lookback: {{ row.maximum_lookback_seconds }} seconds
            </p>
          </div>
          <nav
            aria-label="Template review pages"
            class="flex flex-wrap items-center justify-between gap-2 p-4 text-sm"
          >
            <button
              v-if="review.templates.page > 1"
              id="fleet-start-templates-previous"
              :disabled="locked"
              class="text-primary"
              @click="preview(review.requirements.page, review.templates.page - 1)"
            >
              Previous</button
            ><span class="text-xs text-base-content/60">Page {{ review.templates.page }}</span
            ><button
              v-if="review.templates.more"
              id="fleet-start-templates-next"
              :disabled="locked"
              class="text-primary"
              @click="preview(review.requirements.page, review.templates.page + 1)"
            >
              Next
            </button>
          </nav>
        </CadencePanel>
      </div>
      <footer class="space-y-3 border border-primary/30 bg-primary/[0.035] p-5">
        <p class="text-sm text-base-content/70">
          Create a queued run using this policy and these exact inputs. If they change before
          creation, review them again.
        </p>
        <details>
          <summary class="cursor-pointer text-xs text-base-content/60">Input fingerprint</summary>
          <p class="mt-2 break-all font-mono text-xs text-base-content/50">
            {{ review.evidence.input_sha256 }}
          </p>
        </details>
        <p
          v-if="review.requirements.total + review.eligible_occurrence_count === 0"
          id="fleet-start-no-demand"
          class="text-sm text-warning"
        >
          No active or newly generated demand overlaps this horizon.
        </p>
        <button
          id="fleet-start-create"
          type="button"
          class="btn btn-primary btn-sm"
          :disabled="!canCreate"
          @click="create()"
        >
          {{ pending === "create" ? "Creating…" : "Create queued run" }}
        </button>
      </footer>
    </section>
  </main>
  <section v-else id="fleet-start-unavailable" role="alert" class="space-y-3 p-6">
    <h1 class="text-xl font-semibold">Fleet creation unavailable</h1>
    <p class="text-sm text-base-content/60">Current policy evidence could not be verified.</p>
    <button
      v-if="connected"
      id="fleet-start-retry"
      class="btn btn-ghost btn-sm"
      :disabled="!!pending"
      @click="refresh()"
    >
      Retry
    </button>
    <p v-if="notice" role="status">{{ notice }}</p>
  </section>
</template>
