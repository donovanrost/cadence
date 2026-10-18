<script setup lang="ts">
import StatusBadge from "../StatusBadge.vue";
import CadenceDiagnosticsSectionFrame from "@cadence/ui/CadenceDiagnosticsSectionFrame.vue";
import type { DiagnosticSeverity, Diagnostics } from "./presentation_types";

defineProps<{ diagnostics: Diagnostics }>();

const diagnosticHeaderIcons: Record<DiagnosticSeverity, string> = {
  error: "hero-exclamation-triangle",
  warning: "hero-exclamation-circle",
  info: "hero-information-circle",
};

const diagnosticHeaderIconClasses: Record<DiagnosticSeverity, string> = {
  error: "border-error/35 bg-error/10 text-error",
  warning: "border-warning/35 bg-warning/10 text-warning",
  info: "border-info/35 bg-info/10 text-info",
};

const diagnosticRailClasses: Record<DiagnosticSeverity, string> = {
  error: "bg-error",
  warning: "bg-warning",
  info: "bg-info",
};

const diagnosticItemIcons: Record<DiagnosticSeverity, string> = {
  error: "hero-x-circle text-error",
  warning: "hero-exclamation-circle text-warning",
  info: "hero-information-circle text-info",
};
</script>

<template>
  <CadenceDiagnosticsSectionFrame
    :id="diagnostics.id"
    :role="diagnostics.role"
    aria-live="polite"
    :data-diagnostic-severity="diagnostics.severity"
    :data-diagnostic-count="diagnostics.count"
    :data-diagnostic-total="diagnostics.total_count"
  >
    <template #header>
      <div
        class="grid size-9 place-items-center border"
        :class="diagnosticHeaderIconClasses[diagnostics.severity]"
      >
        <span
          class="size-4"
          :class="diagnosticHeaderIcons[diagnostics.severity]"
          aria-hidden="true"
        ></span>
      </div>
      <div class="min-w-0">
        <div class="flex flex-wrap items-center gap-x-3 gap-y-1">
          <h2 class="text-sm font-semibold uppercase tracking-[0.14em]">
            {{ diagnostics.title }}
          </h2>
          <span class="font-mono text-[0.65rem] uppercase tracking-[0.16em] text-base-content/45">
            {{ diagnostics.count_label }}
          </span>
        </div>
        <p v-if="diagnostics.description" class="mt-1 text-sm text-base-content/65">
          {{ diagnostics.description }}
        </p>
      </div>
      <StatusBadge
        :status="
          diagnostics.severity === 'error'
            ? 'blocked'
            : diagnostics.severity === 'warning'
              ? 'attention'
              : 'info'
        "
        :label="diagnostics.label"
      />
    </template>

    <div :id="diagnostics.items_id" class="divide-y divide-base-300/60">
      <article
        v-for="item in diagnostics.items"
        :id="item.id"
        :key="item.diagnostic_id"
        :data-diagnostic-code="item.code"
        :data-diagnostic-severity="item.severity"
        class="group grid grid-cols-[0.25rem_minmax(0,1fr)_auto] gap-4 px-4 py-3"
      >
        <span class="rounded-full" :class="diagnosticRailClasses[item.severity]"></span>
        <div class="min-w-0">
          <div class="flex flex-wrap items-center gap-2">
            <span class="font-mono text-[0.62rem] uppercase tracking-[0.13em] text-base-content/45">
              {{ item.code }}
            </span>
            <h3 class="text-sm font-medium text-base-content">{{ item.title }}</h3>
          </div>
          <p class="mt-1 text-xs leading-5 text-base-content/60">{{ item.detail }}</p>
        </div>
        <div class="flex items-center gap-3 self-center">
          <span
            v-if="item.value"
            class="max-w-56 truncate font-mono text-xs text-base-content/65"
            >{{ item.value }}</span
          >
          <span
            class="size-4 shrink-0"
            :class="diagnosticItemIcons[item.severity]"
            aria-hidden="true"
          ></span>
        </div>
      </article>
    </div>
  </CadenceDiagnosticsSectionFrame>
</template>
