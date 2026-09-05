<script setup>
import CadenceField from "./ui/components/CadenceField.vue";
import TimeRangeRecents from "./TimeRangeRecents.vue";

const props = defineProps({
  root: { type: Object, required: true },
  heading: { type: Object, required: true },
  form: { type: Object, required: true },
  validation: { type: Object, default: null },
  recents: { type: Object, required: true },
});

const emit = defineEmits(["recents-loaded", "select-range"]);

const forwardRecentsLoaded = (payload) => emit("recents-loaded", payload);
const forwardSelectRange = (payload) => emit("select-range", payload);
</script>

<template>
  <div v-bind="props.root.attrs">
    <p v-bind="props.heading.attrs">{{ props.heading.text }}</p>
    <form v-bind="props.form.attrs">
      <CadenceField
        :wrapper-class="props.form.from.wrapper_class"
        :label="props.form.from.label.text"
        :label-class="props.form.from.label.class"
      >
        <input v-bind="props.form.from.attrs" />
      </CadenceField>
      <div :class="props.form.to.margin_class">
        <CadenceField
          :wrapper-class="props.form.to.field.wrapper_class"
          :label="props.form.to.field.label.text"
          :label-class="props.form.to.field.label.class"
        >
          <input v-bind="props.form.to.field.attrs" />
        </CadenceField>
      </div>
      <button v-bind="props.form.submit.attrs">{{ props.form.submit.text }}</button>
    </form>
    <span v-if="props.validation" v-bind="props.validation.attrs">
      {{ props.validation.text }}
    </span>
    <div v-bind="props.recents.attrs">
      <TimeRangeRecents
        :ranges="props.recents.ranges"
        @recents-loaded="forwardRecentsLoaded"
        @select-range="forwardSelectRange"
      />
    </div>
  </div>
</template>
