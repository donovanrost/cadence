<script setup lang="ts">
import LiveVueDemo from "./LiveVueDemo.vue"

type RawAttrs = Record<string, string>

type Presentation = {
  root: {
    attrs: RawAttrs
  }
  header: {
    attrs: RawAttrs
    body: {attrs: RawAttrs}
    content: {attrs: RawAttrs}
    title: {attrs: RawAttrs; text: string}
    subtitle: {attrs: RawAttrs; text: string}
  }
  demo: {
    attrs: RawAttrs
    message: string
  }
}

const props = defineProps<{presentation: Presentation}>()
</script>

<template>
  <div v-bind="props.presentation.root.attrs">
    <header v-bind="props.presentation.header.attrs">
      <div v-bind="props.presentation.header.body.attrs">
        <div v-bind="props.presentation.header.content.attrs">
          <h1 v-bind="props.presentation.header.title.attrs">
            {{ props.presentation.header.title.text }}
          </h1>
          <p v-bind="props.presentation.header.subtitle.attrs">
            {{ props.presentation.header.subtitle.text }}
          </p>
        </div>
      </div>
    </header>

    <div v-bind="props.presentation.demo.attrs">
      <LiveVueDemo :message="props.presentation.demo.message" />
    </div>
  </div>
</template>
