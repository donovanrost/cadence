<script setup lang="ts">
import { ref } from "vue";
import type { OpsPagePort, OpsPageReadPort } from "@cadence/plugin-sdk/ops-pages";
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import CommandAuthoring from "./CommandAuthoring.vue";
import type { AuthoringPage, AuthoringPrerequisite } from "./contracts";

defineOptions({ inheritAttrs: false });
const props = defineProps<{
  page: AuthoringPage | AuthoringPrerequisite;
  port: OpsPagePort;
  readPort: OpsPageReadPort;
  refresh: () => Promise<void>;
}>();
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
</script>
<template>
  <CommandAuthoring v-if="'catalog' in page" :page="page" :port="port" :read-port="readPort" />
  <section v-else id="command-authoring-prerequisite" class="space-y-6">
    <CadencePageHeading>
      <template #title>Create command request</template>
    </CadencePageHeading>
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
          :href="`/missions/${encodeURIComponent(page.context.missionId)}/ops/commands`"
          >Back to commands</a
        >
      </div>
      <p v-if="feedback" role="status">{{ feedback }}</p>
    </div>
  </section>
</template>
