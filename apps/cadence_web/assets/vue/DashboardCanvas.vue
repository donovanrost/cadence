<script setup>
import DashboardComparisonInspector from "./DashboardComparisonInspector.vue"
import DashboardGrid from "./DashboardGrid.vue"

defineProps({
  presentation: {type: Object, required: true},
})

const emit = defineEmits(["layout_changed"])
const forwardLayoutChanged = (payload) => emit("layout_changed", payload)

// A section's disclosure state belongs to this client-rendered canvas. Keep
// the browser's latest state across LiveVue prop updates while retaining the
// server-presented open value for a section's first render.
const sectionOpenByKey = new Map()
const sectionOpen = (group) =>
  sectionOpenByKey.has(group.key)
    ? sectionOpenByKey.get(group.key)
    : Object.hasOwn(group.section.root.attrs, "open")
const rememberSectionOpen = (group, event) => {
  sectionOpenByKey.set(group.key, event.currentTarget.open)
}
</script>

<template>
  <div v-bind="presentation.root.attrs">
    <div v-bind="presentation.content.attrs">
      <section
        v-for="group in presentation.groups"
        :key="group.key"
        v-bind="group.root.attrs"
      >
        <details
          v-if="group.section"
          v-bind="group.section.root.attrs"
          :open="sectionOpen(group)"
          @toggle="rememberSectionOpen(group, $event)"
        >
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

          <DashboardGrid
            :presentation="group.grid"
            @layout_changed="forwardLayoutChanged"
          />
        </details>

        <template v-else>
          <header v-if="group.header" v-bind="group.header.attrs">
            <span v-bind="group.header.icon.attrs"></span>
            <h2 v-bind="group.header.title.attrs">{{ group.header.title.text }}</h2>
            <span v-if="group.header.count" v-bind="group.header.count.attrs">{{
              group.header.count.text
            }}</span>
          </header>

          <DashboardGrid
            :presentation="group.grid"
            @layout_changed="forwardLayoutChanged"
          />
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
