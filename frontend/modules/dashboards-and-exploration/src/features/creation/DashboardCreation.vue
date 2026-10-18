<script setup lang="ts">
import { computed, ref, watch } from "vue";
import type { OpsPagePort } from "@cadence/plugin-sdk/ops-pages";
import type { CreationState } from "./contracts";
import type { DashboardPayload } from "./presentation.contracts";
import CreationPresentation from "./CreationPresentation.vue";
import { presentation, editorHref } from "./presentation";
import { record, identity, integer } from "./validation";
const props = defineProps<{
  state: CreationState;
  port: OpsPagePort;
  refresh: () => Promise<void>;
}>();
const sequence = ref(props.state.sequence),
  locked = ref(props.state.phase === "submitted");
const pending = ref(false),
  notice = ref("");
const view = computed(() => presentation(props.state.model));
watch(
  () => props.state,
  (next) => {
    sequence.value = Math.max(sequence.value, next.sequence);
    if (next.phase === "submitted") locked.value = true;
  },
);
async function save(payload: DashboardPayload) {
  if (locked.value) return;
  locked.value = true;
  pending.value = true;
  notice.value = "";
  const requested = ++sequence.value;
  try {
    const response = record(
      await props.port.execute("create", {
        sequence: requested,
        source_version: props.state.model.source?.version ?? null,
        dashboard: payload.dashboard,
      }),
    );
    if (integer(response.sequence) !== requested) throw Error("Unconfirmed sequence");
    if (
      response.status === "invalid" &&
      ["fields", "document", "source_changed"].includes(response.code as string)
    ) {
      notice.value =
        response.code === "document"
          ? "Enter a valid Cadence dashboard document or export bundle."
          : response.code === "source_changed"
            ? "The source changed. Refresh and review it before cloning."
            : "Enter a name of at most 512 bytes, a description of at most 4096 bytes, and valid dashboard JSON (at most 256 KiB) when importing.";
      locked.value = false;
      return;
    }
    if (response.status !== "ok") throw Error("Unconfirmed creation");
    const receipt = record(response.data),
      id = identity(receipt.dashboard_id);
    if (receipt.mode !== props.state.model.mode || integer(receipt.version, 1) !== 1)
      throw Error("Unconfirmed receipt");
    notice.value = "Dashboard created. Opening the editor…";
    props.port.navigate(editorHref(props.state.model.mission_id, id));
  } catch {
    notice.value =
      "Creation could not be confirmed. Submission remains locked; inspect the directory before starting again.";
  } finally {
    pending.value = false;
  }
}
async function refreshPage() {
  if (pending.value) return;
  pending.value = true;
  try {
    await props.refresh();
  } catch {
    notice.value = "Creation context could not be refreshed.";
  } finally {
    pending.value = false;
  }
}
</script>
<template>
  <section id="dashboard-creation-feature">
    <div
      v-if="notice || locked"
      id="dashboard-creation-outcome"
      role="status"
      class="border border-warning/30 bg-base-200 p-3 text-sm"
    >
      {{
        pending
          ? "Creating dashboard…"
          : notice || "A previous creation may have completed. Submission remains locked."
      }}
    </div>
    <CreationPresentation v-bind="view" :disabled="locked" preserve-draft @save="save" />
    <button
      id="dashboard-creation-refresh"
      type="button"
      class="btn btn-sm m-5"
      :disabled="pending"
      @click="refreshPage"
    >
      Refresh context
    </button>
  </section>
</template>
