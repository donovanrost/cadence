<script setup lang="ts">
import { computed } from "vue";
import type { OpsContactRequirementListProps } from "./OpsContactRequirementList.contracts";
import { admitRequirementList } from "./requirement-list";
import CadenceOpsViewport from "@cadence/ui/CadenceOpsViewport.vue";

const props = defineProps<OpsContactRequirementListProps>();
const admitted = computed(() => admitRequirementList(props));
</script>

<template>
  <CadenceOpsViewport v-if="admitted" :id="page.id">
    <div class="">
      <div class="mb-5 grid border border-base-300 bg-base-200/25 sm:grid-cols-4">
        <div
          v-for="step in page.journey_steps"
          :key="step.number"
          :class="[
            'border-b border-base-300 px-4 py-3 sm:border-b-0 sm:border-r last:border-r-0',
            step.active && 'bg-primary/[0.06]',
          ]"
        >
          <p class="font-mono text-[0.6rem] tracking-[0.2em] text-primary/60">
            {{ step.number }}
          </p>
          <p class="mt-1 text-sm font-semibold">{{ step.label }}</p>
          <p class="mt-0.5 text-xs text-base-content/45">{{ step.detail }}</p>
        </div>
      </div>

      <nav aria-label="Requirement lifecycle" class="mb-4 flex flex-wrap gap-2">
        <a
          v-for="filter in filters"
          :id="filter.id"
          :key="filter.id"
          :href="filter.href"
          :aria-current="filter.active ? 'page' : undefined"
          data-phx-link="redirect"
          data-phx-link-state="push"
          :class="['btn btn-sm', filter.active && 'btn-primary']"
        >
          {{ filter.label }}
        </a>
      </nav>

      <div
        v-if="requirements.length === 0"
        :id="page.empty_state.id"
        class="border border-dashed border-base-300 bg-base-200/20 px-6 py-16 text-center"
      >
        <span
          class="hero-clipboard-document-list mx-auto h-8 w-8 text-primary/40"
          aria-hidden="true"
        ></span>
        <h2 class="mt-4 text-lg font-semibold">{{ page.empty_state.title }}</h2>
        <p class="mx-auto mt-2 max-w-xl text-sm text-base-content/60">
          {{ page.empty_state.description }}
        </p>
      </div>

      <div :id="page.list_id" class="space-y-3">
        <a
          v-for="row in requirements"
          :id="row.__dom_id"
          :key="row.id"
          :href="row.detail_href"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="group block border border-base-300 bg-base-200/20 transition-colors hover:border-primary/50 hover:bg-primary/[0.03]"
        >
          <div
            class="grid gap-4 px-4 py-4 md:grid-cols-[minmax(0,1.4fr)_minmax(15rem,0.8fr)_auto] md:items-center"
          >
            <div class="min-w-0">
              <div class="flex flex-wrap items-center gap-2">
                <span :class="row.priority.class" :data-tone="row.priority.tone">
                  {{ row.priority.label }}
                </span>
                <span
                  class="font-mono text-[0.65rem] uppercase tracking-wider text-base-content/45"
                >
                  {{ row.version_direction }}
                </span>
              </div>
              <h2 class="mt-2 truncate text-base font-semibold group-hover:text-primary">
                {{ row.intent_label }}
              </h2>
              <p class="mt-1 truncate text-sm text-base-content/55">
                {{ row.outcome_detail }}
              </p>
            </div>
            <div>
              <p class="hud-label">{{ row.window.label }}</p>
              <p class="mt-1 font-mono text-xs tabular-nums text-base-content/75">
                {{ row.window.detail }}
              </p>
            </div>
            <div class="min-w-36 border-l border-base-300 pl-4">
              <p class="hud-label">Requirement state</p>
              <p class="mt-1 text-sm font-semibold text-base-content/80">
                {{ row.lifecycle.label }}
              </p>
              <p class="mt-1 font-mono text-[0.65rem] text-base-content/45">
                {{ row.lifecycle.detail }}
              </p>
            </div>
          </div>
        </a>
      </div>
      <nav aria-label="Requirements pages" class="mt-5 flex flex-wrap items-center gap-3">
        <a
          v-if="pagination.previous_href"
          id="requirements-previous-page"
          :href="pagination.previous_href"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="btn btn-sm"
          >Previous page</a
        >
        <span class="font-mono text-xs text-base-content/60">{{ pagination.label }}</span>
        <a
          v-if="pagination.next_href"
          id="requirements-next-page"
          :href="pagination.next_href"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="btn btn-sm"
          >Next page</a
        >
      </nav>
    </div>
  </CadenceOpsViewport>
  <CadenceOpsViewport v-else id="contact-requirements-unavailable">
    <p role="alert">Contact requirements could not be loaded. Refresh this page to try again.</p>
  </CadenceOpsViewport>
</template>
