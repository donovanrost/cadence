<script setup lang="ts">
type Presentation = {
  link: {
    attrs: Record<string, string>
    class: string
    label: string
  }
  tagline: {
    class: string
    text: string
  }
}

defineProps<{presentation: Presentation}>()
</script>

<template>
  <a :class="presentation.link.class" v-bind="presentation.link.attrs">
    {{ presentation.link.label }}
  </a>
  <p :class="presentation.tagline.class">{{ presentation.tagline.text }}</p>
</template>
