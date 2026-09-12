<script setup lang="ts">
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import StatusBadge from "../../shared/StatusBadge.vue";
import CadenceCard from "@cadence/ui/CadenceCard.vue";
import CadenceTableFrame from "@cadence/ui/CadenceTableFrame.vue";
import CadenceMenuItem from "@cadence/ui/CadenceMenuItem.vue";
import CadenceModalMenu from "@cadence/ui/CadenceModalMenu.vue";

type StatusTone = "ready" | "attention" | "blocked" | "info";

type Status = {
  tone: StatusTone;
  label: string;
};

type ReadinessCard = {
  title: string;
  value: number;
  status: Status;
  description: string;
};

type Setup = {
  eyebrow: string;
  title: string;
  description: string;
  issue_count: number;
  status: Status;
  empty: boolean;
  empty_state: {
    title: string;
    action_label: string;
    action_href: string;
  };
};

type MissionOverview = {
  mission: {
    eyebrow: string;
    display_name: string;
    slug: string;
  };
  readiness_cards: ReadinessCard[];
  setup: Setup;
};

type SpacecraftReadinessRow = {
  id: string;
  __dom_id: string;
  actions_id: string;
  spacecraft_display_name: string;
  spacecraft_id: string;
  scid_label: string;
  endpoint_label: string;
  endpoint_ref_label: string;
  path_label: string;
  path_detail: string;
  status: StatusTone;
  status_label: string;
  issue: string;
  primary_action: string;
  primary_action_href: string;
  view_spacecraft_href: string;
};

defineProps<{
  overview: MissionOverview;
  spacecraft_readiness: SpacecraftReadinessRow[];
}>();
</script>

<template>
  <CadencePageHeading>
    <template #title>{{ overview.mission.display_name }}</template>
    <template #eyebrow>{{ overview.mission.eyebrow }}</template>
    <template #description>{{ overview.mission.slug }}</template>
  </CadencePageHeading>

  <div class="grid gap-4 md:grid-cols-3">
    <CadenceCard
      v-for="card in overview.readiness_cards"
      :key="card.title"
      class="card bg-base-200 border border-base-300"
      body-class="card-body p-6"
    >
      <div class="flex items-start justify-between gap-4">
        <p class="hud-label">{{ card.title }}</p>
        <StatusBadge :status="card.status.tone" :label="card.status.label" />
      </div>
      <p class="mt-3 mc-value-large text-base-content">{{ card.value }}</p>
      <p class="mt-2 text-sm text-base-content/70">{{ card.description }}</p>
    </CadenceCard>
  </div>

  <CadenceCard class="card bg-base-200 border border-base-300" body-class="card-body p-6">
    <div class="flex items-start justify-between gap-4">
      <div>
        <p class="hud-label mb-2">{{ overview.setup.eyebrow }}</p>
        <h2 class="text-lg font-semibold">{{ overview.setup.title }}</h2>
        <p class="mt-1 max-w-2xl text-sm text-base-content/70">
          {{ overview.setup.description }}
        </p>
      </div>
      <div class="flex flex-wrap items-center justify-end gap-2">
        <StatusBadge :status="overview.setup.status.tone" :label="overview.setup.status.label" />
      </div>
    </div>

    <div id="spacecraft-readiness-section" class="mt-6 overflow-x-auto">
      <div v-if="overview.setup.empty" id="spacecraft-readiness-empty">
        <div class="rounded border border-dashed border-base-300/60 bg-base-100/30 p-8 text-center">
          <p class="hud-label">{{ overview.setup.empty_state.title }}</p>
          <div class="mt-5">
            <a
              :href="overview.setup.empty_state.action_href"
              data-phx-link="redirect"
              data-phx-link-state="push"
              class="btn btn-primary btn-sm"
            >
              <span class="hero-plus -ml-0.5 mr-1 h-4 w-4"></span>
              {{ overview.setup.empty_state.action_label }}
            </a>
          </div>
        </div>
      </div>

      <CadenceTableFrame v-else id="mission-spacecraft-readiness">
        <thead>
          <tr>
            <th class="hud-label">Spacecraft</th>
            <th class="hud-label">SCID</th>
            <th class="hud-label">Runtime Identity</th>
            <th class="hud-label">Downlink Link</th>
            <th class="hud-label">Status</th>
            <th class="hud-label text-right">Actions</th>
          </tr>
        </thead>
        <tbody id="spacecraft-readiness-table">
          <tr
            v-for="row in spacecraft_readiness"
            :id="row.__dom_id"
            :key="row.id"
            class="border-l-2 border-l-transparent hover:border-l-primary/60 transition-colors"
          >
            <td>
              <div class="font-medium">{{ row.spacecraft_display_name }}</div>
              <div class="font-mono text-xs text-base-content/60">
                {{ row.spacecraft_id }}
              </div>
            </td>
            <td class="font-mono text-sm text-primary/80">{{ row.scid_label }}</td>
            <td>
              <div class="text-sm">{{ row.endpoint_label }}</div>
              <div class="font-mono text-xs text-base-content/60">
                {{ row.endpoint_ref_label }}
              </div>
            </td>
            <td>
              <div class="text-sm">{{ row.path_label }}</div>
              <div class="text-xs text-base-content/60">{{ row.path_detail }}</div>
            </td>
            <td>
              <StatusBadge :status="row.status" :label="row.status_label" />
              <p class="mt-1 max-w-xs text-xs text-base-content/70">{{ row.issue }}</p>
            </td>
            <td class="text-right">
              <div :id="row.actions_id" class="cadence-overlay">
                <CadenceModalMenu side="bottom" align="end" :side-offset="4">
                  <template #trigger="{ open }">
                    <button
                      :id="`${row.actions_id}-trigger`"
                      type="button"
                      aria-label="Actions"
                      :aria-controls="open ? `${row.actions_id}-menu` : undefined"
                      class="cadence-overlay-trigger btn btn-ghost btn-xs"
                    >
                      <span class="hero-ellipsis-vertical h-5 w-5"></span>
                    </button>
                  </template>
                  <template #content="{ open }">
                    <div
                      :id="`${row.actions_id}-menu`"
                      :aria-labelledby="`${row.actions_id}-trigger`"
                      class="z-50 w-52 rounded-box border border-base-300 bg-base-100 p-2 shadow-lg"
                    >
                      <CadenceMenuItem :active="open">
                        <a
                          :href="row.primary_action_href"
                          data-phx-link="redirect"
                          data-phx-link-state="push"
                          class="flex w-full cursor-pointer items-center gap-2 rounded px-3 py-2 text-left text-xs text-base-content/70 outline-none hover:bg-base-200 hover:text-base-content focus-visible:bg-base-200 focus-visible:text-base-content"
                          >{{ row.primary_action }}</a
                        >
                      </CadenceMenuItem>
                      <CadenceMenuItem :active="open">
                        <a
                          :href="row.view_spacecraft_href"
                          data-phx-link="redirect"
                          data-phx-link-state="push"
                          class="flex w-full cursor-pointer items-center gap-2 rounded px-3 py-2 text-left text-xs text-base-content/70 outline-none hover:bg-base-200 hover:text-base-content focus-visible:bg-base-200 focus-visible:text-base-content"
                          >View spacecraft</a
                        >
                      </CadenceMenuItem>
                    </div>
                  </template>
                </CadenceModalMenu>
              </div>
            </td>
          </tr>
        </tbody>
      </CadenceTableFrame>
    </div>
  </CadenceCard>
</template>
