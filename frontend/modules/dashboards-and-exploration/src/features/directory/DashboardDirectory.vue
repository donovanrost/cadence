<script setup lang="ts">
import { computed, ref, watch } from "vue";
import type { OpsPagePort } from "@cadence/plugin-sdk/ops-pages";
import type { DirectoryState } from "./contracts";
import type { FilterValues, RestorePayload, StarPayload } from "./presentation.contracts";
import DirectoryPresentation from "./DirectoryPresentation.vue";
import { directoryHref, presentation } from "./presentation";
import { integer, record } from "./validation";
const props = defineProps<{
  state: DirectoryState;
  port: OpsPagePort;
  refresh: () => Promise<void>;
}>();
const sequence = ref(props.state.sequence);
const locked = ref(props.state.phase === "submitted");
const pending = ref(false);
const notice = ref("");
watch(
  () => props.state,
  (next) => {
    sequence.value = Math.max(sequence.value, next.sequence);
    if (next.phase === "submitted") locked.value = true;
  },
);
const model = computed(() => presentation(props.state.model, locked.value));
function filter({ directory }: { directory: FilterValues }) {
  if (!pending.value) props.port.navigate(directoryHref(props.state.model.mission_id, directory));
}
async function effect(event: "star" | "restore", payload: StarPayload | RestorePayload) {
  if (locked.value) return;
  const row = props.state.model.rows.find((row) => row.id === payload["dashboard-id"]);
  if (!row) return;
  locked.value = true;
  pending.value = true;
  notice.value = "";
  try {
    const requestedSequence = sequence.value + 1;
    sequence.value = requestedSequence;
    const response = record(
      await props.port.execute(event, {
        dashboard_id: row.id,
        expected_version: row.version,
        sequence: requestedSequence,
        ...(event === "star" ? { starred: !row.starred } : {}),
      }),
    );
    sequence.value = integer(response.sequence);
    if (response.status === "rejected") {
      locked.value = false;
      notice.value = "The request was rejected. Refresh before trying again.";
      return;
    }
    if (
      response.status !== "ok" ||
      sequence.value !== requestedSequence ||
      record(response.data).dashboard_id !== row.id
    )
      throw Error("Unconfirmed action");
    const receipt = record(response.data);
    if (
      (event === "star" && receipt.starred !== !row.starred) ||
      (event === "restore" && receipt.lifecycle !== "active")
    )
      throw Error("Unconfirmed action");
    notice.value = event === "star" ? "Dashboard preference saved." : "Dashboard restored.";
    // Refresh before unlocking so a second action cannot use stale observed data.
    await props.refresh();
    locked.value = false;
  } catch {
    notice.value =
      "The outcome could not be confirmed. Actions remain locked; refresh to inspect current state.";
  } finally {
    pending.value = false;
  }
}
async function refresh() {
  if (pending.value) return;
  pending.value = true;
  try {
    await props.refresh();
  } catch {
    notice.value = "The directory could not be refreshed.";
  } finally {
    pending.value = false;
  }
}
</script>
<template>
  <section id="dashboard-directory-feature">
    <div
      v-if="notice || locked"
      id="dashboard-directory-outcome"
      role="status"
      class="border border-warning/30 bg-base-200 p-3 text-sm"
    >
      {{
        pending
          ? "Updating dashboard directory…"
          : notice || "A previous action has an uncertain outcome. Actions remain locked."
      }}
      <button
        id="dashboard-directory-refresh"
        type="button"
        class="btn btn-sm ml-3"
        :disabled="pending"
        @click="refresh"
      >
        Refresh directory
      </button>
    </div>
    <DirectoryPresentation
      v-bind="model"
      @filter_dashboards="filter"
      @toggle_dashboard_star="effect('star', $event)"
      @restore_dashboard="effect('restore', $event)"
    />
    <nav
      v-if="state.model.pages > 1"
      id="dashboard-directory-pagination"
      aria-label="Dashboard directory pages"
      class="flex items-center justify-between p-3"
    >
      <a
        v-if="state.model.filters.page > 1"
        id="dashboard-directory-previous"
        :href="
          directoryHref(state.model.mission_id, state.model.filters, state.model.filters.page - 1)
        "
        class="btn btn-sm"
        >Previous</a
      >
      <span>Page {{ state.model.filters.page }} of {{ state.model.pages }}</span>
      <a
        v-if="state.model.filters.page < state.model.pages"
        id="dashboard-directory-next"
        :href="
          directoryHref(state.model.mission_id, state.model.filters, state.model.filters.page + 1)
        "
        class="btn btn-sm"
        >Next</a
      >
    </nav>
  </section>
</template>
