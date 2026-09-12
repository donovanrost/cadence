<script setup>
import ClipboardButton from "@cadence/ui/CadenceClipboardButton.vue";
import DashboardComparisonInspectorHeader from "./DashboardComparisonInspectorHeader.vue";
import DashboardComparisonRollup from "./DashboardComparisonRollup.vue";

defineProps({
  presentation: { type: Object, required: true },
});
</script>

<template>
  <aside v-if="presentation.inspector" v-bind="presentation.inspector.root.attrs">
    <div v-bind="presentation.inspector.accent.attrs"></div>
    <div v-bind="presentation.inspector.header_host.attrs">
      <DashboardComparisonInspectorHeader :presentation="presentation.inspector.header" />
    </div>
    <div v-bind="presentation.inspector.body.attrs">
      <DashboardComparisonRollup :presentation="presentation.rollup">
        <template #open-findings-copy>
          <div
            v-if="presentation.rollup.open_findings_copy"
            v-bind="presentation.rollup.open_findings_copy.host.attrs"
          >
            <ClipboardButton v-bind="presentation.rollup.open_findings_copy.props" />
          </div>
        </template>
        <template #preset-copy>
          <div
            v-if="presentation.rollup.preset_copy"
            v-bind="presentation.rollup.preset_copy.host.attrs"
          >
            <ClipboardButton v-bind="presentation.rollup.preset_copy.props" />
          </div>
        </template>
      </DashboardComparisonRollup>
    </div>
  </aside>

  <DashboardComparisonRollup v-else :presentation="presentation.rollup">
    <template #open-findings-copy>
      <div
        v-if="presentation.rollup.open_findings_copy"
        v-bind="presentation.rollup.open_findings_copy.host.attrs"
      >
        <ClipboardButton v-bind="presentation.rollup.open_findings_copy.props" />
      </div>
    </template>
    <template #preset-copy>
      <div
        v-if="presentation.rollup.preset_copy"
        v-bind="presentation.rollup.preset_copy.host.attrs"
      >
        <ClipboardButton v-bind="presentation.rollup.preset_copy.props" />
      </div>
    </template>
  </DashboardComparisonRollup>
</template>
