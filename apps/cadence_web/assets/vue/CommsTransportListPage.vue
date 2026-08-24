<script setup lang="ts">
import CommsTransportList from "./CommsTransportList.vue"

type Attrs = Record<string, string>

type ElementPresentation = {
  attrs: Attrs
}

type TextPresentation = ElementPresentation & {
  text: string
}

type CommsTransportListProps = InstanceType<typeof CommsTransportList>["$props"]

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
    title: TextPresentation & {
      suffix: TextPresentation
    }
    subtitle: TextPresentation
    actions: {
      attrs: Attrs
      new_transport: TextPresentation & {
        icon: ElementPresentation
      }
    }
  }
  empty_state: {
    attrs: Attrs
    title: TextPresentation
    description: TextPresentation
    action_container: ElementPresentation
    action: TextPresentation & {
      icon: ElementPresentation
    }
  } | null
  card: {
    attrs: Attrs
    body: ElementPresentation
    list_component: {
      attrs: Attrs
      props: CommsTransportListProps
    }
  } | null
}

const props = defineProps<{presentation: Presentation}>()
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
            <span v-bind="props.presentation.header.title.suffix.attrs">
              {{ props.presentation.header.title.suffix.text }}
            </span>
          </h1>
          <p v-bind="props.presentation.header.subtitle.attrs">
            {{ props.presentation.header.subtitle.text }}
          </p>
        </div>
        <div v-bind="props.presentation.header.actions.attrs">
          <a v-bind="props.presentation.header.actions.new_transport.attrs">
            <span v-bind="props.presentation.header.actions.new_transport.icon.attrs"></span>
            {{ props.presentation.header.actions.new_transport.text }}
          </a>
        </div>
      </div>
    </header>

    <div v-if="props.presentation.empty_state" v-bind="props.presentation.empty_state.attrs">
      <p v-bind="props.presentation.empty_state.title.attrs">
        {{ props.presentation.empty_state.title.text }}
      </p>
      <p v-bind="props.presentation.empty_state.description.attrs">
        {{ props.presentation.empty_state.description.text }}
      </p>
      <div v-bind="props.presentation.empty_state.action_container.attrs">
        <a v-bind="props.presentation.empty_state.action.attrs">
          <span v-bind="props.presentation.empty_state.action.icon.attrs"></span>
          {{ props.presentation.empty_state.action.text }}
        </a>
      </div>
    </div>

    <section v-else-if="props.presentation.card" v-bind="props.presentation.card.attrs">
      <div v-bind="props.presentation.card.body.attrs">
        <div v-bind="props.presentation.card.list_component.attrs">
          <CommsTransportList v-bind="props.presentation.card.list_component.props" />
        </div>
      </div>
    </section>
  </div>
</template>
