<script setup lang="ts">
import CommsOverview from "./CommsOverview.vue"

type Attrs = Record<string, string>

type ElementPresentation = {
  attrs: Attrs
}

type TextPresentation = ElementPresentation & {
  text: string
}

type CommsOverviewProps = InstanceType<typeof CommsOverview>["$props"]

type Presentation = {
  root: ElementPresentation
  header: {
    attrs: Attrs
    body: ElementPresentation
    content: ElementPresentation
    eyebrow: TextPresentation
    title: TextPresentation
    title_suffix: TextPresentation
  }
  overview: CommsOverviewProps["overview"]
}

const props = defineProps<{presentation: Presentation}>()
</script>

<template>
  <div v-bind="props.presentation.root.attrs">
    <header v-bind="props.presentation.header.attrs">
      <div v-bind="props.presentation.header.body.attrs">
        <div v-bind="props.presentation.header.content.attrs">
          <p v-bind="props.presentation.header.eyebrow.attrs">
            {{ props.presentation.header.eyebrow.text }}
          </p>
          <h1 v-bind="props.presentation.header.title.attrs">
            {{ props.presentation.header.title.text }}
            <span v-bind="props.presentation.header.title_suffix.attrs">
              {{ props.presentation.header.title_suffix.text }}
            </span>
          </h1>
        </div>
      </div>
    </header>

    <CommsOverview :overview="props.presentation.overview" />
  </div>
</template>
