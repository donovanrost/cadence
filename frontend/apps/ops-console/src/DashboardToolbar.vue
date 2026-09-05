<script setup lang="ts">
import { computed } from "vue";

import DashboardComparisonToggle from "./DashboardComparisonToggle.vue";
import DashboardEditorActions from "./DashboardEditorActions.vue";
import DashboardRuntimeContextSelector from "./DashboardRuntimeContextSelector.vue";
import DashboardRuntimeControls from "./DashboardRuntimeControls.vue";
import DashboardTimePicker from "./DashboardTimePicker.vue";
import DashboardToolbarMenu from "./DashboardToolbarMenu.vue";
import WidgetWarning from "./WidgetWarning.vue";
import CadencePopover from "./ui/reka/CadencePopover.vue";

type ToolbarPresentation = Record<string, any>;

const props = defineProps<{ presentation: ToolbarPresentation }>();
const emit = defineEmits(["recents-loaded", "select-range"]);

const forwardRecentsLoaded = (payload: unknown) => emit("recents-loaded", payload);
const forwardSelectRange = (payload: unknown) => emit("select-range", payload);

const operationalScopeIdentity = computed(() => {
  const identity = props.presentation.viewer?.operational_scope.root.attrs.id;
  return typeof identity === "string" ? identity : null;
});

const operationalScopePanelAttrs = computed(() => {
  const attrs = { ...props.presentation.viewer?.operational_scope.panel.attrs };
  delete attrs.hidden;
  return attrs;
});

const dataHealthIdentity = computed(() => {
  const identity = props.presentation.data_health?.root.attrs.id;
  return typeof identity === "string" ? identity : null;
});

const dataHealthPanelAttrs = computed(() => {
  const attrs = { ...props.presentation.data_health?.panel.attrs };
  delete attrs.hidden;
  return attrs;
});
</script>

<template>
  <div v-bind="props.presentation.root.attrs">
    <div :class="props.presentation.title.wrapper_class">
      <h1 v-bind="props.presentation.title.attrs">{{ props.presentation.title.text }}</h1>
    </div>

    <div v-if="props.presentation.viewer" v-bind="props.presentation.viewer.root.attrs">
      <CadencePopover
        :identity="operationalScopeIdentity"
        side="bottom"
        align="start"
        :collision-padding="16"
        v-bind="props.presentation.viewer.operational_scope.root.attrs"
      >
        <template #trigger="{ open }">
          <button
            v-bind="props.presentation.viewer.operational_scope.trigger.attrs"
            :aria-expanded="String(open)"
          >
            <span :class="props.presentation.viewer.operational_scope.trigger.label.class">
              {{ props.presentation.viewer.operational_scope.trigger.label.text }}
            </span>
            <span :class="props.presentation.viewer.operational_scope.trigger.value.class">
              {{ props.presentation.viewer.operational_scope.trigger.value.text }}
            </span>
            <span
              v-if="props.presentation.viewer.operational_scope.trigger.override"
              v-bind="props.presentation.viewer.operational_scope.trigger.override.attrs"
              >{{ props.presentation.viewer.operational_scope.trigger.override.text }}</span
            >
            <span :class="props.presentation.viewer.operational_scope.trigger.icon_class"></span>
          </button>
        </template>

        <template #content="{ open }">
          <section v-bind="operationalScopePanelAttrs" :hidden="!open">
            <div :class="props.presentation.viewer.operational_scope.panel.header.class">
              <span
                :class="props.presentation.viewer.operational_scope.panel.header.icon_class"
              ></span>
              <div>
                <p :class="props.presentation.viewer.operational_scope.panel.header.title.class">
                  {{ props.presentation.viewer.operational_scope.panel.header.title.text }}
                </p>
                <p
                  :class="
                    props.presentation.viewer.operational_scope.panel.header.description.class
                  "
                >
                  {{ props.presentation.viewer.operational_scope.panel.header.description.text }}
                </p>
              </div>
            </div>
            <div :class="props.presentation.viewer.operational_scope.panel.body.class">
              <div
                v-if="props.presentation.viewer.operational_scope.panel.body.context"
                v-bind="props.presentation.viewer.operational_scope.panel.body.context_host.attrs"
              >
                <DashboardRuntimeContextSelector
                  :presentation="props.presentation.viewer.operational_scope.panel.body.context"
                />
              </div>

              <details
                v-bind="props.presentation.viewer.operational_scope.panel.body.query_options.attrs"
              >
                <summary
                  v-bind="
                    props.presentation.viewer.operational_scope.panel.body.query_options.summary
                      .attrs
                  "
                >
                  <span
                    :class="
                      props.presentation.viewer.operational_scope.panel.body.query_options.summary
                        .leading_class
                    "
                  >
                    <span
                      :class="
                        props.presentation.viewer.operational_scope.panel.body.query_options.summary
                          .icon_class
                      "
                    ></span>
                    <span
                      :class="
                        props.presentation.viewer.operational_scope.panel.body.query_options.summary
                          .copy_class
                      "
                    >
                      <span
                        :class="
                          props.presentation.viewer.operational_scope.panel.body.query_options
                            .summary.title.class
                        "
                        >{{
                          props.presentation.viewer.operational_scope.panel.body.query_options
                            .summary.title.text
                        }}</span
                      >
                      <span
                        :class="
                          props.presentation.viewer.operational_scope.panel.body.query_options
                            .summary.description.class
                        "
                        >{{
                          props.presentation.viewer.operational_scope.panel.body.query_options
                            .summary.description.text
                        }}</span
                      >
                    </span>
                  </span>
                  <span
                    :class="
                      props.presentation.viewer.operational_scope.panel.body.query_options.summary
                        .chevron_class
                    "
                  ></span>
                </summary>
                <div
                  v-bind="
                    props.presentation.viewer.operational_scope.panel.body.query_options.panel.attrs
                  "
                >
                  <div
                    v-bind="
                      props.presentation.viewer.operational_scope.panel.body.query_options.panel
                        .runtime_controls_host.attrs
                    "
                  >
                    <DashboardRuntimeControls
                      :runtime_controls="
                        props.presentation.viewer.operational_scope.panel.body.query_options.panel
                          .runtime_controls
                      "
                    />
                  </div>
                </div>
              </details>
            </div>
          </section>
        </template>
      </CadencePopover>

      <div v-bind="props.presentation.viewer.time_picker_host.attrs">
        <DashboardTimePicker
          :presentation="props.presentation.viewer.time_picker"
          @recents-loaded="forwardRecentsLoaded"
          @select-range="forwardSelectRange"
        />
      </div>
    </div>

    <div
      v-if="props.presentation.comparison_toggle"
      id="dashboard-comparison-toggle-component"
      class="contents"
    >
      <DashboardComparisonToggle :presentation="props.presentation.comparison_toggle" />
    </div>

    <CadencePopover
      v-if="props.presentation.data_health"
      :identity="dataHealthIdentity"
      side="bottom"
      align="end"
      :collision-padding="16"
      v-bind="props.presentation.data_health.root.attrs"
    >
      <template #trigger="{ open }">
        <button v-bind="props.presentation.data_health.trigger.attrs" :aria-expanded="String(open)">
          <span v-bind="props.presentation.data_health.trigger.badge.attrs">
            <span :class="props.presentation.data_health.trigger.badge.icon_class"></span>
            <span>{{ props.presentation.data_health.trigger.badge.count }}</span>
            <span class="hidden sm:inline">{{
              props.presentation.data_health.trigger.badge.label
            }}</span>
          </span>
        </button>
      </template>

      <template #content="{ open }">
        <section v-bind="dataHealthPanelAttrs" :hidden="!open">
          <div :class="props.presentation.data_health.panel.body.class">
            <div :class="props.presentation.data_health.panel.body.header.class">
              <span :class="props.presentation.data_health.panel.body.header.icon_class"></span>
              <div :class="props.presentation.data_health.panel.body.header.copy_class">
                <p :class="props.presentation.data_health.panel.body.header.title.class">
                  {{ props.presentation.data_health.panel.body.header.title.text }}
                </p>
                <p :class="props.presentation.data_health.panel.body.header.summary.class">
                  {{ props.presentation.data_health.panel.body.header.summary.text }}
                </p>
              </div>
            </div>
            <div
              v-if="props.presentation.data_health.panel.body.warnings.length"
              :class="props.presentation.data_health.panel.body.warnings_class"
            >
              <div
                v-for="warning in props.presentation.data_health.panel.body.warnings"
                :key="warning.component_id"
                :id="warning.component_id"
                class="contents"
              >
                <WidgetWarning :presentation="warning" />
              </div>
            </div>
            <p
              v-if="props.presentation.data_health.panel.body.degraded_message"
              :class="props.presentation.data_health.panel.body.degraded_message.class"
            >
              {{ props.presentation.data_health.panel.body.degraded_message.text }}
            </p>
            <a v-bind="props.presentation.data_health.panel.body.action.attrs">
              <span :class="props.presentation.data_health.panel.body.action.icon_class"></span>
              {{ props.presentation.data_health.panel.body.action.text }}
            </a>
            <a
              v-if="props.presentation.data_health.panel.body.diagnostics_action"
              v-bind="props.presentation.data_health.panel.body.diagnostics_action.attrs"
            >
              <span
                :class="props.presentation.data_health.panel.body.diagnostics_action.icon_class"
              ></span>
              {{ props.presentation.data_health.panel.body.diagnostics_action.text }}
            </a>
          </div>
        </section>
      </template>
    </CadencePopover>

    <div
      v-if="props.presentation.editor_actions"
      id="dashboard-editor-actions-component"
      class="contents"
    >
      <DashboardEditorActions :presentation="props.presentation.editor_actions" />
    </div>

    <DashboardToolbarMenu :presentation="props.presentation.menu" />
  </div>
</template>
