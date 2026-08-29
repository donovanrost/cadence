<script setup>
import {reactive} from "vue"

import CadenceCollapsible from "./ui/reka/CadenceCollapsible.vue"
import CadenceCollapsibleContent from "./ui/reka/CadenceCollapsibleContent.vue"
import CadenceCollapsibleTrigger from "./ui/reka/CadenceCollapsibleTrigger.vue"
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
const sectionOpenByKey = reactive(new Map())
const sectionOpen = (group) => {
  if (!sectionOpenByKey.has(group.key)) {
    sectionOpenByKey.set(group.key, Object.hasOwn(group.section.root.attrs, "open"))
  }

  return sectionOpenByKey.get(group.key)
}
const rememberSectionOpen = (group, open) => {
  sectionOpenByKey.set(group.key, open)
}
const sectionContentId = (group) => `${group.section.root.attrs.id}-content`
const sectionRootAttrs = (group) => {
  const {open: _serverOpen, ...attrs} = group.section.root.attrs
  return attrs
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
        <CadenceCollapsible
          v-if="group.section"
          :content-id="sectionContentId(group)"
          :open="sectionOpen(group)"
          :unmount-on-hide="false"
          @request-change="rememberSectionOpen(group, $event)"
        >
          <div v-bind="sectionRootAttrs(group)">
            <CadenceCollapsibleTrigger>
              <button type="button" v-bind="group.section.summary.attrs">
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
              </button>
            </CadenceCollapsibleTrigger>

            <CadenceCollapsibleContent>
              <div class="contents">
                <DashboardGrid
                  :presentation="group.grid"
                  :section-open="sectionOpen(group)"
                  @layout_changed="forwardLayoutChanged"
                />
              </div>
            </CadenceCollapsibleContent>
          </div>
        </CadenceCollapsible>

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
