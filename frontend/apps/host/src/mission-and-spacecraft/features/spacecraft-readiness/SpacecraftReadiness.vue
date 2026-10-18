<script setup lang="ts">
import { useManagementHeader } from "@cadence/plugin-sdk/page-header";
import StatusBadge from "../../shared/StatusBadge.vue";
import CadenceCard from "@cadence/ui/CadenceCard.vue";
import CadenceDataRow from "@cadence/ui/CadenceDataRow.vue";

import { computed } from "vue";
import ReadinessContributionCard from "./ReadinessContributionCard.vue";
import { admitContributions } from "./validation";
import type { ReadinessData } from "./contracts";
const props = defineProps<ReadinessData>();
const contributions = computed(() => admitContributions(props.contributions, props.context));
const overall = computed(() =>
  contributions.value.some((value) => value === null || value.availability === "unavailable")
    ? { tone: "blocked" as const, label: "Contribution unavailable" }
    : props.page.status,
);
const tones = { ready: "success", attention: "warning", blocked: "error", info: "info" } as const;
useManagementHeader("/missions/:mission_id/spacecraft/:spacecraft_id/readiness", () => ({
  title: props.page.title,
  description: props.page.subtitle,
  facts: [props.page.title_suffix],
  status: { tone: tones[overall.value.tone], label: overall.value.label },
}));
</script>
<template>
  <div :id="page.id" class="space-y-6">
    <div class="grid gap-4 xl:grid-cols-2">
      <CadenceCard
        v-for="panel in panels"
        :id="panel.id"
        :key="panel.id"
        class="card bg-base-200 border border-base-300"
        body-class="card-body p-6"
      >
        <div class="flex items-start justify-between gap-4">
          <p class="hud-label">{{ panel.title }}</p>
          <StatusBadge :status="panel.status.tone" :label="panel.status.label" />
        </div>
        <h2 class="mt-3 text-base font-semibold">{{ panel.status.label }}</h2>
        <p class="mt-1 text-sm text-base-content/70">{{ panel.description }}</p>

        <div class="mt-5 space-y-1">
          <CadenceDataRow
            v-for="detail in panel.details"
            :key="detail.label"
            row-class="hud-data-row"
            label-class="hud-data-label"
            :label="detail.label"
          >
            <span class="hud-data-value">{{ detail.value }}</span>
          </CadenceDataRow>

          <div v-if="panel.application_list !== null" :id="panel.application_list.id">
            <p
              :id="panel.application_list.empty_state.id"
              class="hidden only:block text-sm text-base-content/60"
            >
              {{ panel.application_list.empty_state.description }}
            </p>
            <div
              v-for="application in applications"
              :id="application.id"
              :key="application.application_key"
            >
              <CadenceDataRow
                row-class="hud-data-row"
                label-class="hud-data-label"
                :label="application.display_name"
              >
                <span class="hud-data-value">{{ application.status.label }}</span>
              </CadenceDataRow>
            </div>
          </div>
        </div>

        <a
          :href="panel.action.href"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="btn btn-primary btn-sm mt-5"
          >{{ panel.action.label }}</a
        >
      </CadenceCard>
      <ReadinessContributionCard
        v-for="(contribution, index) in contributions"
        :key="index"
        :index="index"
        :contribution="contribution"
      />
    </div>
  </div>
</template>
