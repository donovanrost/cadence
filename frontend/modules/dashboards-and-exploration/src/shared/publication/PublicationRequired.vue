<script setup lang="ts">
import { computed, ref } from "vue";
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import type { PublicationRequirement } from "./contracts";
const props = defineProps<{ requirement: PublicationRequirement; refresh: () => Promise<void> }>();
const directory = computed(
  () => `/missions/${encodeURIComponent(props.requirement.mission_id)}/ops/dashboards`,
);
const pending = ref(false),
  feedback = ref("");
async function refreshPage() {
  if (pending.value) return;
  pending.value = true;
  feedback.value = "";
  try {
    await props.refresh();
  } catch {
    feedback.value = "Publication could not be checked. Try refreshing again.";
  } finally {
    pending.value = false;
  }
}
</script>
<template>
  <section id="dashboard-publication-required" class="space-y-6">
    <CadencePageHeading><template #title>Dashboard not published</template></CadencePageHeading>
    <div class="card border border-base-300 bg-base-200 p-6 space-y-4">
      <p>
        This dashboard has no published version. Viewing and execution diagnostics become available
        after an author publishes it.
      </p>
      <p v-if="requirement.author">Open the editor to prepare and publish the dashboard.</p>
      <div class="flex flex-wrap gap-3">
        <a
          v-if="requirement.author"
          id="dashboard-publication-editor"
          class="btn btn-primary btn-sm"
          :href="`${directory}/${encodeURIComponent(requirement.dashboard_id)}/edit`"
          >Open editor</a
        >
        <button
          id="dashboard-publication-refresh"
          type="button"
          class="btn btn-outline btn-sm"
          :disabled="pending"
          @click="refreshPage"
        >
          {{ pending ? "Checking…" : "Refresh publication" }}
        </button>
        <a id="dashboard-publication-directory" class="btn btn-ghost btn-sm" :href="directory"
          >Back to dashboards</a
        >
      </div>
      <p v-if="feedback" role="status">{{ feedback }}</p>
    </div>
  </section>
</template>
