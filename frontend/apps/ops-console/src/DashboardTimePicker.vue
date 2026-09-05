<script setup lang="ts">
import { computed } from "vue";

import DashboardAbsoluteRangePane from "./DashboardAbsoluteRangePane.vue";
import DashboardQuickRangeList from "./DashboardQuickRangeList.vue";
import DashboardSelectedDatumActions from "./DashboardSelectedDatumActions.vue";
import DashboardTimeReplay from "./DashboardTimeReplay.vue";
import CadencePopover from "./ui/reka/CadencePopover.vue";

type AttrValue = string | boolean | null;
type Attrs = Record<string, AttrValue>;

type AbsoluteRangePresentation = InstanceType<typeof DashboardAbsoluteRangePane>["$props"];
type QuickRangesPresentation = InstanceType<
  typeof DashboardQuickRangeList
>["$props"]["presentation"];
type ReplayPresentation = InstanceType<typeof DashboardTimeReplay>["$props"]["presentation"];
type SelectedDatumPresentation = InstanceType<
  typeof DashboardSelectedDatumActions
>["$props"]["presentation"];

type ButtonPresentation = {
  attrs: Attrs;
  icon_class: string;
};

type DashboardTimePickerPresentation = {
  shift_back: ButtonPresentation | false;
  overlay: {
    root: { attrs: Attrs };
    trigger: {
      attrs: Attrs;
      live_indicator: { attrs: Attrs };
      active_range: { attrs: Attrs; text: string };
      icon_class: string;
    };
    panel: {
      attrs: Attrs;
      header: {
        class: string;
        icon_class: string;
        title: { class: string; text: string };
        description: { class: string; text: string };
      };
      body: {
        class: string;
        controls: { attrs: Attrs };
      };
    };
  };
  time_picker: {
    class: string;
    absolute_range_host: { attrs: Attrs };
    absolute_range: AbsoluteRangePresentation;
    quick_ranges_host: { attrs: Attrs };
    quick_ranges: QuickRangesPresentation;
  };
  replay_host: { attrs: Attrs };
  replay: ReplayPresentation;
  selected_datum_host: { attrs: Attrs };
  selected_datum: SelectedDatumPresentation;
  shift_forward: ButtonPresentation | false;
  zoom_out: ButtonPresentation | false;
};

const props = defineProps<{ presentation: DashboardTimePickerPresentation }>();
const emit = defineEmits(["recents-loaded", "select-range"]);

const forwardRecentsLoaded = (payload: unknown) => emit("recents-loaded", payload);
const forwardSelectRange = (payload: unknown) => emit("select-range", payload);

const overlayIdentity = computed(() => {
  const identity = props.presentation.overlay.root.attrs.id;
  return typeof identity === "string" ? identity : null;
});

const panelAttrs = computed(() => {
  const attrs = { ...props.presentation.overlay.panel.attrs };
  delete attrs.hidden;
  return attrs;
});
</script>

<template>
  <button v-if="props.presentation.shift_back" v-bind="props.presentation.shift_back.attrs">
    <span :class="props.presentation.shift_back.icon_class"></span>
  </button>

  <CadencePopover
    :identity="overlayIdentity"
    side="bottom"
    align="end"
    :collision-padding="16"
    v-bind="props.presentation.overlay.root.attrs"
  >
    <template #trigger="{ open }">
      <button v-bind="props.presentation.overlay.trigger.attrs" :aria-expanded="open">
        <span v-bind="props.presentation.overlay.trigger.live_indicator.attrs"></span>
        <span v-bind="props.presentation.overlay.trigger.active_range.attrs">
          {{ props.presentation.overlay.trigger.active_range.text }}
        </span>
        <span :class="props.presentation.overlay.trigger.icon_class"></span>
      </button>
    </template>

    <template #content="{ open }">
      <section v-bind="panelAttrs" :hidden="!open">
        <div :class="props.presentation.overlay.panel.header.class">
          <span :class="props.presentation.overlay.panel.header.icon_class"></span>
          <div>
            <p :class="props.presentation.overlay.panel.header.title.class">
              {{ props.presentation.overlay.panel.header.title.text }}
            </p>
            <p :class="props.presentation.overlay.panel.header.description.class">
              {{ props.presentation.overlay.panel.header.description.text }}
            </p>
          </div>
        </div>

        <div :class="props.presentation.overlay.panel.body.class">
          <div v-bind="props.presentation.overlay.panel.body.controls.attrs">
            <div :class="props.presentation.time_picker.class">
              <div v-bind="props.presentation.time_picker.absolute_range_host.attrs">
                <DashboardAbsoluteRangePane
                  v-bind="props.presentation.time_picker.absolute_range"
                  @recents-loaded="forwardRecentsLoaded"
                  @select-range="forwardSelectRange"
                />
              </div>
              <div v-bind="props.presentation.time_picker.quick_ranges_host.attrs">
                <DashboardQuickRangeList
                  :presentation="props.presentation.time_picker.quick_ranges"
                />
              </div>
            </div>
            <div v-bind="props.presentation.replay_host.attrs">
              <DashboardTimeReplay :presentation="props.presentation.replay" />
            </div>
            <div v-bind="props.presentation.selected_datum_host.attrs">
              <DashboardSelectedDatumActions :presentation="props.presentation.selected_datum" />
            </div>
          </div>
        </div>
      </section>
    </template>
  </CadencePopover>

  <button v-if="props.presentation.shift_forward" v-bind="props.presentation.shift_forward.attrs">
    <span :class="props.presentation.shift_forward.icon_class"></span>
  </button>

  <button v-if="props.presentation.zoom_out" v-bind="props.presentation.zoom_out.attrs">
    <span :class="props.presentation.zoom_out.icon_class"></span>
  </button>
</template>
