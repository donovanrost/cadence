<script setup>
import DashboardComparisonInspector from "./DashboardComparisonInspector.vue"
import DashboardGrid from "./DashboardGrid.vue"
import DashboardWidget from "./DashboardWidget.vue"

defineProps({
  presentation: {type: Object, required: true},
})

const emit = defineEmits(["layout_changed"])
const forwardLayoutChanged = (payload) => emit("layout_changed", payload)
</script>

<template>
  <div v-bind="presentation.root.attrs">
    <div v-bind="presentation.content.attrs">
      <section
        v-for="group in presentation.groups"
        :key="group.key"
        v-bind="group.root.attrs"
      >
        <details v-if="group.section" v-bind="group.section.root.attrs">
          <summary v-bind="group.section.summary.attrs">
            <span v-bind="group.section.summary.icon.attrs"></span>
            <div v-bind="group.section.summary.copy.attrs">
              <h2 v-bind="group.section.summary.copy.title.attrs">{{
                group.section.summary.copy.title.text
              }}</h2>
              <p
                v-if="group.section.summary.copy.description"
                v-bind="group.section.summary.copy.description.attrs"
              >{{ group.section.summary.copy.description.text }}</p>
            </div>
            <span
              v-if="group.section.summary.count"
              v-bind="group.section.summary.count.attrs"
            >{{ group.section.summary.count.text }}</span>
          </summary>

          <div v-bind="group.grid.root.attrs">
            <div
              v-for="widget in group.grid.widgets"
              :key="widget.key"
              v-bind="widget.shell.attrs"
            >
              <div v-bind="widget.content.attrs">
                <div v-bind="widget.host.attrs">
                  <DashboardWidget :presentation="widget.presentation" />
                </div>
              </div>
            </div>
          </div>
          <div v-bind="group.grid.controller.host.attrs">
            <DashboardGrid
              :target_id="group.grid.controller.props.target_id"
              :edit_mode="group.grid.controller.props.edit_mode"
              :item_ids="group.grid.controller.props.item_ids"
              @layout_changed="forwardLayoutChanged"
            />
          </div>
        </details>

        <template v-else>
          <header v-if="group.header" v-bind="group.header.attrs">
            <span v-bind="group.header.icon.attrs"></span>
            <h2 v-bind="group.header.title.attrs">{{ group.header.title.text }}</h2>
            <span v-if="group.header.count" v-bind="group.header.count.attrs">{{
              group.header.count.text
            }}</span>
          </header>

          <div v-bind="group.grid.root.attrs">
            <div
              v-for="widget in group.grid.widgets"
              :key="widget.key"
              v-bind="widget.shell.attrs"
            >
              <div v-bind="widget.content.attrs">
                <div v-bind="widget.host.attrs">
                  <DashboardWidget :presentation="widget.presentation" />
                </div>
              </div>
            </div>
          </div>
          <div v-bind="group.grid.controller.host.attrs">
            <DashboardGrid
              :target_id="group.grid.controller.props.target_id"
              :edit_mode="group.grid.controller.props.edit_mode"
              :item_ids="group.grid.controller.props.item_ids"
              @layout_changed="forwardLayoutChanged"
            />
          </div>
        </template>
      </section>

      <div v-if="presentation.empty_state" v-bind="presentation.empty_state.wrapper.attrs">
        <div v-bind="presentation.empty_state.card.attrs">
          <span v-bind="presentation.empty_state.icon.attrs"></span>
          <p v-bind="presentation.empty_state.title.attrs">{{
            presentation.empty_state.title.text
          }}</p>
          <p v-bind="presentation.empty_state.message.attrs">{{
            presentation.empty_state.message.text
          }}</p>
          <div v-bind="presentation.empty_state.actions.attrs">
            <button
              v-if="presentation.empty_state.actions.action?.kind === 'button'"
              v-bind="presentation.empty_state.actions.action.attrs"
            >
              <span v-bind="presentation.empty_state.actions.action.icon.attrs"></span>
              {{ presentation.empty_state.actions.action.text }}
            </button>
            <a
              v-else-if="presentation.empty_state.actions.action?.kind === 'link'"
              v-bind="presentation.empty_state.actions.action.attrs"
            >
              <span v-bind="presentation.empty_state.actions.action.icon.attrs"></span>
              {{ presentation.empty_state.actions.action.text }}
            </a>
          </div>
        </div>
      </div>
    </div>

    <div
      v-if="presentation.comparison_inspector"
      v-bind="presentation.comparison_inspector.host.attrs"
    >
      <DashboardComparisonInspector
        :presentation="presentation.comparison_inspector.presentation"
      />
    </div>
  </div>
</template>
