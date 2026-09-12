<script setup lang="ts">
import { inject } from "vue";
import CadencePanel from "@cadence/ui/CadencePanel.vue";
import {
  FLEET_DIRECTORY_PORT,
  fleetStates,
  type OpsFleetPlanningProps,
} from "./OpsFleetPlanning.contracts";
import { fleetBase, fleetPageHref } from "./fleet-directory";
import { useFleetDirectory } from "./fleet-directory-state";
const props = defineProps<OpsFleetPlanningProps>();
const { directory, pending, notice, refresh, connected } = useFleetDirectory(
  () => props.directory,
  props.port ?? inject(FLEET_DIRECTORY_PORT, undefined),
);
const label = (value: string) => value.replaceAll("_", " ");
</script>
<template>
  <main v-if="directory" id="ops-fleet-planning-page" class="space-y-6 p-4 md:p-6">
    <header class="flex flex-wrap items-start justify-between gap-4">
      <div>
        <p class="text-xs uppercase tracking-widest text-base-content/60">
          Planning &amp; contacts
        </p>
        <h1 class="mt-1 text-2xl font-semibold">Fleet Planning</h1>
        <p class="mt-2 max-w-2xl text-sm text-base-content/60">
          Review mission horizons, exact policy inputs, and durable planning progress.
        </p>
      </div>
      <div class="flex flex-wrap gap-2">
        <button
          id="refresh-fleet-planning"
          class="btn btn-ghost btn-sm"
          type="button"
          :disabled="pending || !connected"
          @click="refresh"
        >
          {{ pending ? "Refreshing…" : "Refresh" }}
        </button>
        <a
          id="fleet-planning-policy-link"
          :href="`${fleetBase(directory)}/policy`"
          class="btn btn-ghost btn-sm"
          >Policy</a
        >
        <a
          v-if="directory.active_policy"
          id="new-fleet-planning-run-link"
          :href="`${fleetBase(directory)}/new`"
          class="btn btn-primary btn-sm"
          >Plan horizon</a
        >
      </div>
    </header>
    <p v-if="notice" id="fleet-directory-notice" role="status" class="text-sm text-base-content/70">
      {{ notice }}
    </p>
    <section
      v-if="directory.active_policy"
      id="fleet-planning-active-policy"
      class="border border-base-300 bg-base-200/20 p-4"
    >
      <p class="text-xs uppercase tracking-widest text-base-content/60">
        Approved scheduling boundary
      </p>
      <p class="mt-2 text-sm">
        Policy v{{ directory.active_policy.version }} · Maximum horizon
        {{ directory.active_policy.max_horizon_seconds }} seconds
      </p>
      <p class="mt-1 break-all font-mono text-xs text-base-content/50">
        {{ directory.active_policy.id }}
      </p>
      <p class="mt-1 break-all font-mono text-xs text-base-content/50">
        {{ directory.active_policy.content_sha256 }}
      </p>
    </section>
    <section
      v-else
      id="fleet-planning-policy-required"
      class="border border-warning/35 bg-warning/[0.04] p-4"
    >
      <h2 class="font-semibold text-warning">
        An approved fleet policy is required for new planning.
      </h2>
      <p class="mt-2 text-sm text-base-content/60">
        Existing run evidence remains available. An administrator can configure and approve the
        scheduling boundary.
      </p>
      <a
        id="configure-fleet-planning-policy"
        :href="`${fleetBase(directory)}/policy`"
        class="mt-3 inline-block text-sm text-primary"
        >Review policy</a
      >
    </section>
    <div class="grid gap-5 xl:grid-cols-[minmax(0,1fr)_18rem]">
      <CadencePanel
        class="min-w-0 border border-base-300 bg-base-200/15"
        header-class="border-b border-base-300 p-4"
      >
        <template #header>
          <div class="flex flex-wrap items-end justify-between gap-4">
            <div>
              <h2 class="font-semibold">Run ledger</h2>
              <p class="mt-1 text-xs text-base-content/60">
                {{ directory.runs.entries.length }} on this page · Newest first
              </p>
            </div>
            <form
              id="fleet-directory-filter"
              method="get"
              :action="fleetBase(directory)"
              class="flex min-w-0 max-w-full flex-wrap items-end gap-2"
            >
              <label for="fleet-directory-state" class="min-w-0 max-w-full space-y-1 text-xs"
                ><span class="block text-base-content/60">Lifecycle</span
                ><select
                  id="fleet-directory-state"
                  name="state"
                  :value="directory.query.state ?? ''"
                  class="select select-bordered select-sm max-w-full"
                >
                  <option value="">All states</option>
                  <option v-for="state in fleetStates" :key="state" :value="state">
                    {{ label(state) }}
                  </option>
                </select></label
              >
              <button id="fleet-directory-filter-submit" class="btn btn-ghost btn-sm" type="submit">
                Apply
              </button>
            </form>
          </div>
        </template>
        <p
          v-if="!directory.runs.entries.length"
          id="fleet-planning-runs-empty"
          class="px-4 py-12 text-center text-sm text-base-content/60"
        >
          No runs on this page{{
            directory.query.state ? ` for ${label(directory.query.state)}` : ""
          }}.
        </p>
        <div id="fleet-planning-runs" class="divide-y divide-base-300">
          <article
            v-for="run in directory.runs.entries"
            :id="`fleet-run-${encodeURIComponent(run.id)}`"
            :key="run.id"
            class="space-y-3 p-4"
          >
            <div class="flex flex-wrap items-start justify-between gap-3">
              <a
                :href="`${fleetBase(directory)}/runs/${encodeURIComponent(run.id)}`"
                class="min-w-0 break-all font-mono text-sm text-primary hover:underline"
                >{{ run.id }}</a
              >
              <span
                class="text-xs uppercase tracking-wide"
                :class="
                  run.lifecycle_state === 'failed' || run.lifecycle_state === 'partial'
                    ? 'text-warning'
                    : 'text-base-content/70'
                "
                >{{ label(run.lifecycle_state) }} · {{ run.trigger_kind }}</span
              >
            </div>
            <p class="break-words font-mono text-xs text-base-content/75">
              {{ run.horizon_start }} → {{ run.horizon_end }}
              <span class="text-base-content/45">UTC</span>
            </p>
            <div class="flex flex-wrap gap-x-5 gap-y-2 text-xs text-base-content/60">
              <span>Phase: {{ label(run.phase) }}</span
              ><span>{{ run.requirement_count }} Requirements</span
              ><span>Policy v{{ run.policy_version }}</span>
            </div>
            <p class="break-all text-xs text-base-content/45">Policy {{ run.policy_id }}</p>
            <a
              v-if="run.candidate_plan"
              :href="`/missions/${encodeURIComponent(directory.context.mission_id)}/ops/plans/${encodeURIComponent(run.candidate_plan.id)}?version=${run.candidate_plan.version}`"
              class="inline-block text-xs text-primary hover:underline"
              >Review candidate Plan v{{ run.candidate_plan.version }}</a
            >
          </article>
        </div>
        <nav
          aria-label="Fleet run pages"
          class="flex items-center justify-between border-t border-base-300 p-4 text-sm"
        >
          <a
            v-if="directory.query.page > 1"
            id="fleet-directory-previous"
            :href="fleetPageHref(directory, directory.query.page - 1)"
            class="text-primary"
            >Previous</a
          ><span v-else></span>
          <span class="font-mono text-xs text-base-content/60"
            >Page {{ directory.query.page }}</span
          >
          <a
            v-if="directory.runs.more && directory.query.page < 1000000"
            id="fleet-directory-next"
            :href="fleetPageHref(directory, directory.query.page + 1)"
            class="text-primary"
            >Next</a
          ><span v-else></span>
        </nav>
      </CadencePanel>
      <aside
        id="fleet-planning-recurring-demand-panel"
        class="h-fit border border-base-300 bg-base-200/15 p-4"
      >
        <h2 class="font-semibold">Recurring demand</h2>
        <p class="mt-2 text-sm text-base-content/60">
          Templates generate ordinary Requirements. Each run retains the versions it used; candidate
          Plans follow the approval and execution workflow.
        </p>
        <a
          id="requirement-templates-link"
          :href="`/missions/${encodeURIComponent(directory.context.mission_id)}/ops/requirement-templates`"
          class="mt-4 inline-block text-sm text-primary"
          >Manage templates</a
        >
      </aside>
    </div>
  </main>
  <section v-else id="fleet-directory-unavailable" class="space-y-3 p-6" role="alert">
    <h1 class="text-xl font-semibold">Fleet directory unavailable</h1>
    <p class="text-sm text-base-content/60">Current fleet evidence could not be verified.</p>
    <button
      v-if="connected"
      id="fleet-directory-retry"
      class="btn btn-ghost btn-sm"
      :disabled="pending"
      @click="refresh"
    >
      Retry
    </button>
    <p v-if="notice" role="status">{{ notice }}</p>
  </section>
</template>
