<script setup lang="ts">
import type { WidgetWarningPresentation } from "./WidgetWarning.contracts";

import { computed } from "vue";
import CadencePopover from "@cadence/ui/CadencePopover.vue";

const props = defineProps<{ presentation: WidgetWarningPresentation }>();

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
    side="bottom"
    align="end"
    :side-offset="8"
    :collision-padding="16"
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
          :class="props.presentation.trigger.badge.class"
          v-bind="props.presentation.trigger.badge.attrs"
          >{{ props.presentation.trigger.badge.text }}</span
        >
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
          <p :class="props.presentation.body.message.class">
            {{ props.presentation.body.message.text }}
          </p>
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
          <dl
            v-if="props.presentation.body.details.visible"
            :class="props.presentation.body.details.class"
          >
            <template v-for="row in props.presentation.body.details.rows" :key="row.key">
              <dt :class="row.label.class">{{ row.label.text }}</dt>
              <dd :class="row.value.class" v-bind="row.value.attrs">
                {{ row.value.text }}
              </dd>
            </template>
          </dl>
          <div
            v-if="props.presentation.body.evidence.visible"
            :class="props.presentation.body.evidence.class"
            v-bind="props.presentation.body.evidence.attrs"
          >
            <div :class="props.presentation.body.evidence.heading.class">
              {{ props.presentation.body.evidence.heading.text }}
            </div>
            <div
              v-for="row in props.presentation.body.evidence.rows"
              :key="row.key"
              :class="row.class"
              v-bind="row.attrs"
            >
              <template v-for="field in row.fields" :key="field.key">
                <span :class="field.label.class">{{ field.label.text }}</span>
                <span :class="field.value.class">{{ field.value.text }}</span>
              </template>
            </div>
          </div>
          <div
            v-if="props.presentation.body.links.visible"
            :class="props.presentation.body.links.class"
            v-bind="props.presentation.body.links.attrs"
          >
            <div :class="props.presentation.body.links.heading.class">
              {{ props.presentation.body.links.heading.text }}
            </div>
            <button
              v-for="row in props.presentation.body.links.rows"
              :key="row.key"
              :type="row.type"
              :class="row.class"
              v-bind="row.attrs"
            >
              <template v-for="field in row.fields" :key="field.key">
                <span :class="field.label.class">{{ field.label.text }}</span>
                <span :class="field.value.class">{{ field.value.text }}</span>
              </template>
            </button>
          </div>
        </div>
      </section>
    </template>
  </CadencePopover>
</template>
