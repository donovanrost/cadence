<script setup>
defineProps({
  presentation: { type: Object, required: true },
});
</script>

<template>
  <div v-bind="presentation.root.attrs">
    <p v-if="presentation.empty.visible" v-bind="presentation.empty.attrs">
      {{ presentation.empty.text }}
    </p>

    <article v-for="section in presentation.sections" :key="section.key" v-bind="section.attrs">
      <div v-bind="section.layout.attrs">
        <span v-bind="section.icon.attrs"></span>
        <div v-bind="section.content.attrs">
          <p v-bind="section.content.title.attrs">{{ section.content.title.text }}</p>
          <p v-if="section.content.description.visible" v-bind="section.content.description.attrs">
            {{ section.content.description.text }}
          </p>
          <span v-bind="section.content.default_state.attrs">
            {{ section.content.default_state.text }}
          </span>
        </div>
        <div v-bind="section.actions.attrs">
          <button v-for="button in section.actions.buttons" :key="button.key" v-bind="button.attrs">
            <span v-bind="button.icon.attrs"></span>
          </button>
        </div>
      </div>
    </article>
  </div>
</template>
