<script setup lang="ts">
import { computed } from "vue";
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import { navigateAttrs } from "../../../auth-and-navigation";
import { workspaceGroups } from "../../shared/destinations";
import { readWorkspaceLanding } from "./contracts";

defineOptions({ inheritAttrs: false });
const props = defineProps<{ model: unknown; organizationId: unknown; missionId: unknown }>();
const model = computed(() => {
  try {
    return readWorkspaceLanding(props.model, props.organizationId, props.missionId);
  } catch {
    return null;
  }
});
const groups = computed(() =>
  model.value
    ? workspaceGroups(
        (path) => `/missions/${encodeURIComponent(model.value!.context.mission_id)}/ops/${path}`,
        model.value.can_administer,
      )
    : [],
);
const descriptions: Record<string, string> = {
  observe: "Follow telemetry, investigate changes and inspect mission events.",
  act: "Prepare commands and review operations that need a decision.",
  plan: "Coordinate requirements, contact plans and scheduled passes.",
  system: "Inspect source health and manage historical data workflows.",
};
</script>

<template>
  <section id="ops-workspace-landing" class="space-y-6">
    <template v-if="model">
      <CadencePageHeading>
        <template #eyebrow>{{ model.mission_name }}</template>
        <template #title>Mission Operations</template>
        <template #description
          >Choose a workspace to observe, plan or act on this mission.</template
        >
      </CadencePageHeading>
      <div class="grid gap-4 lg:grid-cols-2">
        <section
          v-for="group in groups"
          :key="group.key"
          :aria-labelledby="`ops-entry-${group.key}`"
          class="card border border-base-300 bg-base-200 p-5"
        >
          <h2
            :id="`ops-entry-${group.key}`"
            class="text-sm font-semibold uppercase tracking-wide text-primary"
          >
            {{ group.label }}
          </h2>
          <p class="mt-2 text-sm leading-6 text-base-content/65">{{ descriptions[group.key] }}</p>
          <nav
            :aria-label="`${group.label} mission operations`"
            class="mt-4 divide-y divide-base-300"
          >
            <a
              v-for="item in group.items"
              :id="`ops-entry-${item.key}`"
              :key="item.key"
              v-bind="navigateAttrs(item.href)"
              class="flex min-h-11 items-center gap-3 py-3 text-sm font-medium text-base-content hover:text-primary focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary"
            >
              <span
                :class="[item.icon, 'h-4 w-4 shrink-0 text-primary/75']"
                aria-hidden="true"
              ></span>
              <span class="min-w-0 flex-1">{{ item.label }}</span>
              <span class="hero-arrow-right h-4 w-4 shrink-0" aria-hidden="true"></span>
            </a>
          </nav>
        </section>
      </div>
    </template>
    <p
      v-else
      id="ops-workspace-landing-unavailable"
      role="alert"
      class="card border border-warning/40 bg-base-200 p-6"
    >
      Mission operations navigation is unavailable. Use the mission navigation to continue.
    </p>
  </section>
</template>
