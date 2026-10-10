<script setup lang="ts">
import { ref } from "vue";
import { useOpsHeader } from "@cadence/plugin-sdk/page-header";
import { href } from "@cadence/plugin-sdk/routes";

/** Shown instead of authoring while the mission has no active command model. */
const props = defineProps<{ missionId: string; refresh: () => Promise<void> }>();
const refreshing = ref(false);
const feedback = ref("");
async function refreshPage() {
  if (refreshing.value) return;
  refreshing.value = true;
  feedback.value = "";
  try {
    await props.refresh();
  } catch {
    feedback.value = "The command model could not be checked. Try refreshing again.";
  } finally {
    refreshing.value = false;
  }
}
useOpsHeader("/missions/:mission_id/ops/commands/new", () => ({
  description: "Command authoring needs an approved mission model activated for this mission.",
  refresh: { run: refreshPage, pending: refreshing.value },
}));
</script>
<template>
  <section id="command-authoring-prerequisite" class="space-y-6">
    <div class="card border border-base-300 bg-base-200 p-6 space-y-4">
      <h2 class="text-lg font-semibold">Command model required</h2>
      <p>
        Command authoring needs an approved mission model activated for this mission. Its command
        catalog is not currently available. Complete the mission model approval and activation
        workflow, then refresh this page.
      </p>
      <div class="flex flex-wrap gap-3">
        <button
          id="command-authoring-prerequisite-refresh"
          type="button"
          class="btn btn-primary btn-sm"
          :disabled="refreshing"
          @click="refreshPage"
        >
          {{ refreshing ? "Checking…" : "Refresh command model" }}
        </button>
        <a
          id="command-authoring-prerequisite-monitor"
          class="btn btn-ghost btn-sm"
          :href="href('/missions/:mission_id/ops/commands', { mission_id: missionId })"
          >Back to commands</a
        >
      </div>
      <p v-if="feedback" role="status">{{ feedback }}</p>
    </div>
  </section>
</template>
