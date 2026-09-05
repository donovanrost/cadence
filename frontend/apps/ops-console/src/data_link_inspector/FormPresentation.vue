<script setup lang="ts">
import type { PropType } from "vue";
import EffectsList from "./EffectsList.vue";
import type { EffectPresentation, FormPresentation } from "./presentation_types";

defineProps({
  presentation: { type: Object as PropType<FormPresentation>, required: true },
  effects: { type: Array as PropType<EffectPresentation[]>, required: true },
  effects_id: { type: String, required: true },
  effect_key_attribute: { type: String, required: true },
});
</script>

<template>
  <form v-bind="presentation.attrs">
    <input v-for="field in presentation.hidden_fields" :key="String(field.id)" v-bind="field" />
    <EffectsList :id="effects_id" :effects="effects" :key_attribute="effect_key_attribute" />
    <div class="grid grid-cols-1 gap-2">
      <div
        v-for="field in presentation.fields"
        :key="String(field.attrs.id)"
        :class="field.wrapper_class"
      >
        <label>
          <span :class="field.label.class">{{ field.label.text }}</span>
          <select v-if="field.options" v-bind="field.attrs">
            <option
              v-for="option in field.options"
              :key="option.value"
              :value="option.value"
              :selected="option.selected"
              :disabled="option.disabled"
              :title="option.title ?? undefined"
            >
              {{ option.label }}
            </option>
          </select>
          <input v-else v-bind="field.attrs" />
        </label>
      </div>
    </div>
    <label v-bind="presentation.confirmation.row.attrs">
      <input v-bind="presentation.confirmation.input.attrs" />
      <span :class="presentation.confirmation.label.class">
        {{ presentation.confirmation.label.text }}
      </span>
    </label>
    <button v-bind="presentation.submit.attrs">
      <span :class="presentation.submit.icon_class"></span>
      {{ presentation.submit.text }}
    </button>
  </form>
</template>
