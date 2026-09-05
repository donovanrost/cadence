<script setup>
import ClipboardButton from "./ClipboardButton.vue"

defineProps({
  presentation: {type: Object, required: true}
})
</script>

<template>
  <div :class="presentation.root.class" v-bind="presentation.root.attrs">
    <div :class="presentation.summary.class">
      <dl :class="presentation.summary.rows_class">
        <template v-for="row in presentation.summary.rows" :key="row.key">
          <dt :class="row.label.class">{{ row.label.text }}</dt>
          <dd :class="row.value.class" v-bind="row.value.attrs">
            {{ row.value.text }}
          </dd>
        </template>
      </dl>

      <div :id="presentation.copy_host.id" :class="presentation.copy_host.class">
        <ClipboardButton v-bind="presentation.copy_props" />
      </div>
    </div>

    <div :class="presentation.counts.class">
      <div
        v-for="row in presentation.counts.rows"
        :key="row.key"
        :class="row.class"
        v-bind="row.attrs"
      >
        <div :class="row.label.class">{{ row.label.text }}</div>
        <div :class="row.value.class">{{ row.value.text }}</div>
      </div>
    </div>

    <dl v-if="presentation.placements.visible" :class="presentation.placements.class">
      <template v-for="row in presentation.placements.rows" :key="row.key">
        <dt :class="row.label.class">{{ row.label.text }}</dt>
        <dd :class="row.value.class" v-bind="row.value.attrs">
          {{ row.value.text }}
        </dd>
      </template>
    </dl>
  </div>
</template>
