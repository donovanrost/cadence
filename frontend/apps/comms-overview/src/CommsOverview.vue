<script setup lang="ts">
import { findingDomId } from "./finding-dom-id";
import CadenceCard from "@cadence/ui/CadenceCard.vue";
import CadenceEmptyStateFrame from "@cadence/ui/CadenceEmptyStateFrame.vue";
import StatusBadge from "./StatusBadge.vue";
import type { CommsOverview } from "./comms-overview";

defineProps<{ overview: CommsOverview }>();
</script>

<template>
  <div id="comms-overview-content" class="space-y-6">
    <CadenceCard
      :id="overview.transport.id"
      class="card border border-base-300 bg-base-200"
      body-class="card-body p-6"
    >
      <div class="flex items-start justify-between gap-4">
        <div>
          <p class="hud-label mb-2">{{ overview.transport.eyebrow }}</p>
          <div class="flex items-baseline gap-4">
            <span class="mc-value-large text-base-content">{{ overview.transport.count }}</span>
            <span class="text-sm text-base-content/60">
              {{ overview.transport.count_label }}
            </span>
          </div>
          <p class="mt-3 max-w-2xl text-sm text-base-content/70">
            {{ overview.transport.description }}
          </p>
        </div>
        <StatusBadge
          :status="overview.transport.status.tone"
          :label="overview.transport.status.label"
        />
      </div>

      <div v-if="overview.transport.empty" class="mt-6">
        <CadenceEmptyStateFrame>
          <template #title>{{ overview.transport.empty_state.title }}</template>
          <template #description>
            {{ overview.transport.empty_state.description }}
          </template>
          <template #action>
            <a
              :href="overview.transport.empty_state.action_href"
              data-phx-link="redirect"
              data-phx-link-state="push"
              class="btn btn-primary btn-sm"
            >
              <span class="hero-plus -ml-0.5 mr-1 h-4 w-4"></span>
              {{ overview.transport.empty_state.action_label }}
            </a>
          </template>
        </CadenceEmptyStateFrame>
      </div>

      <template v-else>
        <ul class="mt-6 grid gap-3 md:grid-cols-2">
          <li v-for="transport in overview.transport.rows" :id="transport.id" :key="transport.id">
            <a
              :href="transport.href"
              data-phx-link="redirect"
              data-phx-link-state="push"
              class="hover-glow-cyan transition-glow block rounded border border-l-2 border-base-300 border-l-transparent bg-base-100/40 p-4 hover:border-l-primary/60"
            >
              <p class="font-medium">{{ transport.display_name }}</p>
              <p class="mt-1 font-mono text-xs text-base-content/60">{{ transport.metadata }}</p>
            </a>
          </li>
        </ul>

        <div class="mt-5 flex gap-4 text-sm">
          <a
            :href="overview.transport.manage_href"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="text-primary hover:underline"
            >{{ overview.transport.manage_label }}</a
          >
          <a
            :href="overview.transport.add_href"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="text-primary hover:underline"
            >{{ overview.transport.add_label }}</a
          >
        </div>
      </template>
    </CadenceCard>

    <CadenceCard
      :id="overview.validation.id"
      class="card border border-base-300 bg-base-200"
      body-class="card-body p-6"
    >
      <div class="flex items-start justify-between gap-4">
        <div>
          <p class="hud-label mb-2">{{ overview.validation.eyebrow }}</p>
          <h2 class="text-lg font-semibold">{{ overview.validation.title }}</h2>
          <p class="mt-1 max-w-2xl text-sm text-base-content/70">
            {{ overview.validation.description }}
          </p>
        </div>
        <div class="flex flex-wrap items-center justify-end gap-2">
          <StatusBadge
            :status="overview.validation.status.tone"
            :label="overview.validation.status.label"
          />
        </div>
      </div>

      <div v-if="overview.validation.empty" class="mt-6">
        <div class="rounded border border-dashed border-base-300/60 bg-base-100/30 p-8 text-center">
          <p class="hud-label">{{ overview.validation.empty_state.title }}</p>
          <p class="mx-auto mt-2 max-w-md text-sm text-base-content/70">
            {{ overview.validation.empty_state.description }}
          </p>
        </div>
      </div>

      <div v-else :id="overview.validation.findings_id" class="mt-6 space-y-5">
        <section
          v-for="group in overview.validation.finding_groups"
          :id="group.id"
          :key="group.id"
          class="space-y-3"
        >
          <div>
            <p class="hud-label mb-1">{{ group.title }}</p>
            <p class="text-sm text-base-content/70">{{ group.description }}</p>
          </div>

          <div
            v-for="(finding, index) in group.findings"
            :id="findingDomId(group.id, finding.id, index)"
            :key="finding.id ?? `${group.id}-${index}`"
            class="border border-base-300 bg-base-100/40 p-4"
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
        </section>
      </div>
    </CadenceCard>
  </div>
</template>
