<script setup lang="ts">
import RuntimeCacheSummary from "./RuntimeCacheSummary.vue";
import RuntimeDegradedSource from "./RuntimeDegradedSource.vue";
import RuntimeDiagnosticsSection from "./RuntimeDiagnosticsSection.vue";
import RuntimeNoRefreshSummary from "./RuntimeNoRefreshSummary.vue";
import RuntimeRecentInvalidations from "./RuntimeRecentInvalidations.vue";

type Attributes = Record<string, string>;
type CacheSummaryPresentation = InstanceType<typeof RuntimeCacheSummary>["$props"]["presentation"];
type DegradedSourcePresentation = InstanceType<
  typeof RuntimeDegradedSource
>["$props"]["presentation"];
type DiagnosticsSectionPresentation = InstanceType<
  typeof RuntimeDiagnosticsSection
>["$props"]["presentation"];
type NoRefreshSummaryPresentation = InstanceType<
  typeof RuntimeNoRefreshSummary
>["$props"]["summary"];
type RecentInvalidationsPresentation = InstanceType<
  typeof RuntimeRecentInvalidations
>["$props"]["presentation"];

type ChildPresentation<T> = {
  root: { attrs: Attributes };
  presentation: T;
};

type Presentation = {
  root: { attrs: Attributes };
  engine_section: ChildPresentation<DiagnosticsSectionPresentation>;
  cache_summary: ChildPresentation<CacheSummaryPresentation> | null;
  runtime_section: ChildPresentation<DiagnosticsSectionPresentation>;
  degraded_source_summary: ChildPresentation<DegradedSourcePresentation> | null;
  degraded_source_drilldowns: ChildPresentation<DegradedSourcePresentation> | null;
  source_capability_postures: ChildPresentation<DegradedSourcePresentation> | null;
  source_dependency_causes: ChildPresentation<DegradedSourcePresentation> | null;
  no_refresh_summary: ChildPresentation<NoRefreshSummaryPresentation> | null;
  invalidation_section: ChildPresentation<DiagnosticsSectionPresentation>;
  recent_invalidations: ChildPresentation<RecentInvalidationsPresentation>;
};

defineProps<{ presentation: Presentation }>();
</script>

<template>
  <div v-bind="presentation.engine_section.root.attrs">
    <RuntimeDiagnosticsSection :presentation="presentation.engine_section.presentation" />
  </div>

  <div v-if="presentation.cache_summary" v-bind="presentation.cache_summary.root.attrs">
    <RuntimeCacheSummary :presentation="presentation.cache_summary.presentation" />
  </div>

  <div v-bind="presentation.runtime_section.root.attrs">
    <RuntimeDiagnosticsSection :presentation="presentation.runtime_section.presentation" />
  </div>

  <div
    v-if="presentation.degraded_source_summary"
    v-bind="presentation.degraded_source_summary.root.attrs"
  >
    <RuntimeDegradedSource :presentation="presentation.degraded_source_summary.presentation" />
  </div>

  <div
    v-if="presentation.degraded_source_drilldowns"
    v-bind="presentation.degraded_source_drilldowns.root.attrs"
  >
    <RuntimeDegradedSource :presentation="presentation.degraded_source_drilldowns.presentation" />
  </div>

  <div
    v-if="presentation.source_capability_postures"
    v-bind="presentation.source_capability_postures.root.attrs"
  >
    <RuntimeDegradedSource :presentation="presentation.source_capability_postures.presentation" />
  </div>

  <div
    v-if="presentation.source_dependency_causes"
    v-bind="presentation.source_dependency_causes.root.attrs"
  >
    <RuntimeDegradedSource :presentation="presentation.source_dependency_causes.presentation" />
  </div>

  <div v-if="presentation.no_refresh_summary" v-bind="presentation.no_refresh_summary.root.attrs">
    <RuntimeNoRefreshSummary :summary="presentation.no_refresh_summary.presentation" />
  </div>

  <div v-bind="presentation.invalidation_section.root.attrs">
    <RuntimeDiagnosticsSection :presentation="presentation.invalidation_section.presentation" />
  </div>

  <div v-bind="presentation.recent_invalidations.root.attrs">
    <RuntimeRecentInvalidations :presentation="presentation.recent_invalidations.presentation" />
  </div>
</template>
