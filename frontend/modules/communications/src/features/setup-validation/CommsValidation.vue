<script setup lang="ts">
import { findingDomId } from "../../shared/finding-dom-id";
import { useManagementHeader } from "@cadence/plugin-sdk/page-header";
import CadenceCard from "@cadence/ui/CadenceCard.vue";
import CadencePanel from "@cadence/ui/CadencePanel.vue";
import CadencePaginationFrame from "@cadence/ui/CadencePaginationFrame.vue";
import type { readValidation } from "./read-validation";
import StatusBadge from "../../shared/StatusBadge.vue";

type Validation = ReturnType<typeof readValidation>["validation"];
const props = defineProps<{ validation: Validation }>();
useManagementHeader("/missions/:mission_id/comms/validation", () => ({
  description: props.validation.subtitle,
  facts: [props.validation.finding_count_suffix, props.validation.status.label],
}));
</script>

<template>
  <div :id="validation.id" class="space-y-6">
    <CadenceCard
      v-if="validation.empty"
      :id="validation.empty_state.id"
      class="card bg-base-200 border border-base-300"
      body-class="card-body p-6"
    >
      <div class="rounded border border-dashed border-base-300/60 bg-base-100/30 p-8 text-center">
        <p class="hud-label">{{ validation.empty_state.title }}</p>
        <p class="mt-2 max-w-md mx-auto text-sm text-base-content/70">
          {{ validation.empty_state.description }}
        </p>
      </div>
    </CadenceCard>

    <div v-else :id="validation.findings_id" class="space-y-5">
      <CadencePanel
        v-for="group in validation.finding_groups"
        :id="group.id"
        :key="group.id"
        class="card bg-base-200 border border-base-300"
        header-class="flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3"
      >
        <template #header>
          <div>
            <h2 class="text-base font-semibold text-base-content">{{ group.title }}</h2>
            <p class="mt-1 text-xs text-base-content/70">{{ group.description }}</p>
          </div>
        </template>
        <div class="card-body p-0">
          <div class="divide-y divide-base-300">
            <div
              v-for="(finding, index) in group.findings"
              :id="findingDomId(group.id, finding.id, index)"
              :key="finding.id ?? `${group.id}-${index}`"
              class="px-4 py-4"
            >
              <div class="flex items-start justify-between gap-4">
                <div>
                  <h3 class="font-semibold">{{ finding.title }}</h3>
                  <p class="mt-1 text-sm text-base-content/70">{{ finding.body }}</p>
                  <a
                    v-if="finding.action_href"
                    :href="finding.action_href"
                    data-phx-link="redirect"
                    data-phx-link-state="push"
                    class="btn btn-primary btn-xs mt-3"
                    >{{ finding.action_label }}</a
                  >
                </div>
                <StatusBadge :status="finding.status.tone" :label="finding.status.label" />
              </div>
            </div>
          </div>
        </div>
      </CadencePanel>
    </div>
    <CadencePaginationFrame
      v-if="validation.pagination.previousHref || validation.pagination.nextHref"
      id="comms-validation-pagination"
    >
      <span class="font-mono text-xs text-base-content/70">{{ validation.pagination.label }}</span>
      <div class="flex items-center gap-2">
        <a
          v-if="validation.pagination.previousHref"
          id="comms-validation-previous"
          :href="validation.pagination.previousHref"
          class="btn btn-ghost btn-xs"
          >Previous</a
        >
        <a
          v-if="validation.pagination.nextHref"
          id="comms-validation-next"
          :href="validation.pagination.nextHref"
          class="btn btn-ghost btn-xs"
          >Next</a
        >
      </div>
    </CadencePaginationFrame>
  </div>
</template>
