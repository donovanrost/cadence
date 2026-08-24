<script setup lang="ts">
import MissionApplications from "./MissionApplications.vue"

type Attrs = Record<string, string>

type ElementPresentation = {
  attrs: Attrs
}

type TextPresentation = ElementPresentation & {
  text: string
}

type MissionApplicationsProps = InstanceType<typeof MissionApplications>["$props"]

type ApplicationEvent = {
  key: string
}

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
    subtitle: TextPresentation
  }
  applications_component: {
    attrs: Attrs
    props: {
      applications: MissionApplicationsProps["applications"]
    }
  }
}

const props = defineProps<{presentation: Presentation}>()

const emit = defineEmits<{
  install: [payload: ApplicationEvent]
  disable: [payload: ApplicationEvent]
  uninstall: [payload: ApplicationEvent]
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
          <p v-bind="props.presentation.header.subtitle.attrs">
            {{ props.presentation.header.subtitle.text }}
          </p>
        </div>
      </div>
    </header>

    <div v-bind="props.presentation.applications_component.attrs">
      <MissionApplications
        :applications="props.presentation.applications_component.props.applications"
        @install="emit('install', $event)"
        @disable="emit('disable', $event)"
        @uninstall="emit('uninstall', $event)"
      />
    </div>
  </div>
</template>
