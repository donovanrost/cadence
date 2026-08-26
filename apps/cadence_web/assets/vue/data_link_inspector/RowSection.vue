<script setup lang="ts">
import type {PropType} from "vue"
import type {RowSectionPresentation} from "./presentation_types"

defineProps({
  presentation: {type: Object as PropType<RowSectionPresentation>, required: true},
})
</script>

<template>
  <section v-bind="presentation.attrs">
    <h3 :class="presentation.heading.class">{{ presentation.heading.text }}</h3>
    <dl :class="presentation.list_class">
      <template v-for="row in presentation.rows" :key="row.key">
        <dt :class="row.label.class">{{ row.label.text }}</dt>
        <dd :class="row.value.class" v-bind="row.value.attrs">{{ row.value.text }}</dd>
      </template>
    </dl>
  </section>
</template>
