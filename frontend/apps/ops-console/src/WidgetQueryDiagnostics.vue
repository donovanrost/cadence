<script setup lang="ts">
import { computed } from "vue";
import CadencePopover from "./ui/reka/CadencePopover.vue";

type Attrs = Record<string, string>;

type IconPresentation = {
  name: string;
  class: string;
};

type TextPresentation = {
  class: string;
  text: string;
};

type RowPresentation = {
  key: string;
  order: number;
  label: TextPresentation & { attrs: Attrs };
  value: TextPresentation & { attrs: Attrs };
};

type WidgetQueryDiagnosticsPresentation = {
  component_id: string;
  overlay: { id: string; class: string; attrs: Attrs };
  trigger: {
    id: string;
    type: string;
    class: string;
    attrs: Attrs;
    content: { class: string; attrs: Attrs; icon: IconPresentation };
  };
  panel: { id: string; class: string; hidden: boolean; attrs: Attrs };
  body: {
    class: string;
    heading: TextPresentation;
    rows_class: string;
    rows: RowPresentation[];
    evidence_button: {
      type: string;
      class: string;
      attrs: Attrs;
      icon: IconPresentation;
      text: string;
    };
  };
};

const props = defineProps<{ presentation: WidgetQueryDiagnosticsPresentation }>();

const panelAttrs = computed(() => {
  const attrs = { ...props.presentation.panel.attrs };
  delete attrs.hidden;
  return attrs;
});
</script>

<template>
  <CadencePopover
    :id="props.presentation.overlay.id"
    :identity="props.presentation.overlay.id"
    :class="props.presentation.overlay.class"
    v-bind="props.presentation.overlay.attrs"
  >
    <template #trigger="{ open }">
      <button
        :id="props.presentation.trigger.id"
        :type="props.presentation.trigger.type"
        :class="props.presentation.trigger.class"
        v-bind="props.presentation.trigger.attrs"
        :aria-expanded="String(open)"
      >
        <span
          :class="props.presentation.trigger.content.class"
          v-bind="props.presentation.trigger.content.attrs"
        >
          <span
            :class="[
              props.presentation.trigger.content.icon.name,
              props.presentation.trigger.content.icon.class,
            ]"
          ></span>
        </span>
      </button>
    </template>

    <template #content="{ open }">
      <section
        :id="props.presentation.panel.id"
        :class="props.presentation.panel.class"
        v-bind="panelAttrs"
        :hidden="!open"
      >
        <div :class="props.presentation.body.class">
          <div :class="props.presentation.body.heading.class">
            {{ props.presentation.body.heading.text }}
          </div>
          <dl :class="props.presentation.body.rows_class">
            <template v-for="row in props.presentation.body.rows" :key="row.key">
              <dt :class="row.label.class" v-bind="row.label.attrs">
                {{ row.label.text }}
              </dt>
              <dd :class="row.value.class" v-bind="row.value.attrs">
                {{ row.value.text }}
              </dd>
            </template>
          </dl>
          <button
            :type="props.presentation.body.evidence_button.type"
            :class="props.presentation.body.evidence_button.class"
            v-bind="props.presentation.body.evidence_button.attrs"
          >
            <span
              :class="[
                props.presentation.body.evidence_button.icon.name,
                props.presentation.body.evidence_button.icon.class,
              ]"
            ></span>
            {{ props.presentation.body.evidence_button.text }}
          </button>
        </div>
      </section>
    </template>
  </CadencePopover>
</template>
