<script setup lang="ts">
import RenameDashboardForm from "./RenameDashboardForm.vue";
import DashboardSectionManager from "./DashboardSectionManager.vue";
import HistoricalWorkflowRequestForm from "./HistoricalWorkflowRequestForm.vue";
import DataLinkInspectorPanel from "./DataLinkInspectorPanel.vue";
import EvidenceInspectorPanel from "./EvidenceInspectorPanel.vue";
import WidgetInspectPanel from "./WidgetInspectPanel.vue";
import RuntimeDiagnosticsPanel from "./RuntimeDiagnosticsPanel.vue";
import VersionHistoryPanel from "./VersionHistoryPanel.vue";
import WidgetForm from "./WidgetForm.vue";

type Attributes = Record<string, string>;

type WrapperPresentation = {
  attrs: Attributes;
};

type DirectChildPresentation<Kind extends string, ChildPresentation> = {
  kind: Kind;
  outer_wrapper: null;
  wrapper: WrapperPresentation;
  presentation: ChildPresentation;
};

type OuterWrappedChildPresentation<Kind extends string, ChildPresentation> = {
  kind: Kind;
  outer_wrapper: WrapperPresentation;
  wrapper: WrapperPresentation;
  presentation: ChildPresentation;
};

type ChildPresentation =
  | DirectChildPresentation<
      "rename_dashboard_form",
      InstanceType<typeof RenameDashboardForm>["$props"]["presentation"]
    >
  | DirectChildPresentation<
      "dashboard_section_manager",
      InstanceType<typeof DashboardSectionManager>["$props"]["presentation"]
    >
  | DirectChildPresentation<
      "historical_workflow_request_form",
      InstanceType<typeof HistoricalWorkflowRequestForm>["$props"]["presentation"]
    >
  | OuterWrappedChildPresentation<
      "data_link_inspector_panel",
      InstanceType<typeof DataLinkInspectorPanel>["$props"]["presentation"]
    >
  | DirectChildPresentation<
      "evidence_inspector_panel",
      InstanceType<typeof EvidenceInspectorPanel>["$props"]["presentation"]
    >
  | DirectChildPresentation<
      "widget_inspect_panel",
      InstanceType<typeof WidgetInspectPanel>["$props"]["presentation"]
    >
  | OuterWrappedChildPresentation<
      "runtime_diagnostics_panel",
      InstanceType<typeof RuntimeDiagnosticsPanel>["$props"]["presentation"]
    >
  | DirectChildPresentation<
      "version_history_panel",
      InstanceType<typeof VersionHistoryPanel>["$props"]["presentation"]
    >
  | DirectChildPresentation<
      "widget_form",
      InstanceType<typeof WidgetForm>["$props"]["presentation"]
    >;

type Presentation = {
  sheet: {
    layer: WrapperPresentation;
    root: WrapperPresentation;
    header: WrapperPresentation & {
      title: WrapperPresentation & { text: string };
      close: WrapperPresentation & {
        icon: WrapperPresentation;
      };
    };
    body: WrapperPresentation;
  };
  child: ChildPresentation;
};

defineProps<{ presentation: Presentation }>();
</script>

<template>
  <div v-bind="presentation.sheet.layer.attrs">
    <section v-bind="presentation.sheet.root.attrs">
      <header v-bind="presentation.sheet.header.attrs">
        <h2 v-bind="presentation.sheet.header.title.attrs">
          {{ presentation.sheet.header.title.text }}
        </h2>
        <button v-bind="presentation.sheet.header.close.attrs">
          <span v-bind="presentation.sheet.header.close.icon.attrs"></span>
        </button>
      </header>

      <div v-bind="presentation.sheet.body.attrs">
        <div
          v-if="presentation.child.kind === 'rename_dashboard_form'"
          v-bind="presentation.child.wrapper.attrs"
        >
          <RenameDashboardForm :presentation="presentation.child.presentation" />
        </div>

        <div
          v-else-if="presentation.child.kind === 'dashboard_section_manager'"
          v-bind="presentation.child.wrapper.attrs"
        >
          <DashboardSectionManager :presentation="presentation.child.presentation" />
        </div>

        <div
          v-else-if="presentation.child.kind === 'historical_workflow_request_form'"
          v-bind="presentation.child.wrapper.attrs"
        >
          <HistoricalWorkflowRequestForm :presentation="presentation.child.presentation" />
        </div>

        <div
          v-else-if="presentation.child.kind === 'data_link_inspector_panel'"
          v-bind="presentation.child.outer_wrapper?.attrs"
        >
          <div v-bind="presentation.child.wrapper.attrs">
            <DataLinkInspectorPanel :presentation="presentation.child.presentation" />
          </div>
        </div>

        <div
          v-else-if="presentation.child.kind === 'evidence_inspector_panel'"
          v-bind="presentation.child.wrapper.attrs"
        >
          <EvidenceInspectorPanel :presentation="presentation.child.presentation" />
        </div>

        <div
          v-else-if="presentation.child.kind === 'widget_inspect_panel'"
          v-bind="presentation.child.wrapper.attrs"
        >
          <WidgetInspectPanel :presentation="presentation.child.presentation" />
        </div>

        <div
          v-else-if="presentation.child.kind === 'runtime_diagnostics_panel'"
          v-bind="presentation.child.outer_wrapper?.attrs"
        >
          <div v-bind="presentation.child.wrapper.attrs">
            <RuntimeDiagnosticsPanel :presentation="presentation.child.presentation" />
          </div>
        </div>

        <div
          v-else-if="presentation.child.kind === 'version_history_panel'"
          v-bind="presentation.child.wrapper.attrs"
        >
          <VersionHistoryPanel :presentation="presentation.child.presentation" />
        </div>

        <div
          v-else-if="presentation.child.kind === 'widget_form'"
          v-bind="presentation.child.wrapper.attrs"
        >
          <WidgetForm :presentation="presentation.child.presentation" />
        </div>
      </div>
    </section>
  </div>
</template>
