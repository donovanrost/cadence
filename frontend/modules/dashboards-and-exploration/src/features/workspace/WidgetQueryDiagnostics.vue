<script setup lang="ts">
import type { WidgetQueryDiagnosticsPresentation } from "./WidgetQueryDiagnostics.contracts";

import { computed } from "vue";
import CadencePopover from "@cadence/ui/CadencePopover.vue";

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
        :aria-expanded="open"
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
