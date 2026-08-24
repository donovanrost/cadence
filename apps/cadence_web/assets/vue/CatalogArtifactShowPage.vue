<script setup lang="ts">
import CatalogArtifactShow from "./CatalogArtifactShow.vue"

type Attrs = Record<string, string>

type ElementPresentation = {
  attrs: Attrs
}

type TextPresentation = ElementPresentation & {
  text: string
}

type CatalogArtifactShowProps = InstanceType<typeof CatalogArtifactShow>["$props"]

type BreadcrumbItem = {
  key: string
  separator: TextPresentation | null
  link: TextPresentation | null
  current: TextPresentation | null
}

type Presentation = {
  root: ElementPresentation
  header: {
    attrs: Attrs
    body: ElementPresentation
    content: ElementPresentation
    breadcrumbs: {
      attrs: Attrs
      items: BreadcrumbItem[]
    }
    title: TextPresentation
  }
  child_wrapper: ElementPresentation
  artifact_show: {
    artifact: CatalogArtifactShowProps["artifact"]
    runs: CatalogArtifactShowProps["runs"]
  }
}

const props = defineProps<{presentation: Presentation}>()

const emit = defineEmits<{
  reimport: []
}>()
</script>

<template>
  <div v-bind="props.presentation.root.attrs">
    <header v-bind="props.presentation.header.attrs">
      <div v-bind="props.presentation.header.body.attrs">
        <div v-bind="props.presentation.header.content.attrs">
          <nav v-bind="props.presentation.header.breadcrumbs.attrs">
            <template v-for="item in props.presentation.header.breadcrumbs.items" :key="item.key">
              <span v-if="item.separator" v-bind="item.separator.attrs">
                {{ item.separator.text }}
              </span>
              <a v-if="item.link" v-bind="item.link.attrs">{{ item.link.text }}</a>
              <span v-if="item.current" v-bind="item.current.attrs">
                {{ item.current.text }}
              </span>
            </template>
          </nav>
          <h1 v-bind="props.presentation.header.title.attrs">
            {{ props.presentation.header.title.text }}
          </h1>
        </div>
      </div>
    </header>

    <div v-bind="props.presentation.child_wrapper.attrs">
      <CatalogArtifactShow
        :artifact="props.presentation.artifact_show.artifact"
        :runs="props.presentation.artifact_show.runs"
        @reimport="emit('reimport')"
      />
    </div>
  </div>
</template>
