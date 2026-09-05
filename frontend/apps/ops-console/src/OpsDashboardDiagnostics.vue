<script setup lang="ts">
import ClipboardButton from "./ClipboardButton.vue"

type RawAttrs = Record<string, string>

type ElementPresentation = {
  attrs: RawAttrs
}

type TextPresentation = ElementPresentation & {
  text: string | number
}

type LinkPresentation = TextPresentation & {
  key?: string
}

type DiagnosticRow = {
  id: string
  __dom_id: string
  attrs: RawAttrs
  header: ElementPresentation
  title: TextPresentation
  status: TextPresentation
  identity: TextPresentation
}

type SelectedDiagnostic = {
  header: {
    attrs: RawAttrs
    content: ElementPresentation
    label: TextPresentation
    title: TextPresentation
    identity: TextPresentation
    copy: {
      component: "ClipboardButton"
      host: ElementPresentation
      props: InstanceType<typeof ClipboardButton>["$props"]
    }
  }
  details: ElementPresentation & {
    items: Array<{
      key: string
      attrs: RawAttrs
      label: TextPresentation
      value: TextPresentation
    }>
  }
  drilldowns: ElementPresentation & {
    links: LinkPresentation[]
  }
}

type Presentation = {
  root: ElementPresentation
  header: {
    attrs: RawAttrs
    inner: ElementPresentation
    content: ElementPresentation
    eyebrow: TextPresentation
    heading: TextPresentation
    copy: TextPresentation
    viewer: LinkPresentation
  }
  content: ElementPresentation
  collections: ElementPresentation & {
    items: Array<{
      key: string
      attrs: RawAttrs
      label: string
      count: TextPresentation
    }>
  }
  workspace: ElementPresentation
  master: ElementPresentation & {
    header: ElementPresentation & {
      label: TextPresentation
      count: TextPresentation
    }
    stream: ElementPresentation & {
      empty: TextPresentation
    }
  }
  detail: ElementPresentation & {
    selected: SelectedDiagnostic | null
    empty: TextPresentation | null
  }
}

const props = defineProps<{
  presentation: Presentation
  diagnostic_rows: DiagnosticRow[]
}>()
</script>

<template>
  <section v-bind="props.presentation.root.attrs">
    <header v-bind="props.presentation.header.attrs">
      <div v-bind="props.presentation.header.inner.attrs">
        <div v-bind="props.presentation.header.content.attrs">
          <p v-bind="props.presentation.header.eyebrow.attrs">
            {{ props.presentation.header.eyebrow.text }}
          </p>
          <h1 v-bind="props.presentation.header.heading.attrs">
            {{ props.presentation.header.heading.text }}
          </h1>
          <p v-bind="props.presentation.header.copy.attrs">
            {{ props.presentation.header.copy.text }}
          </p>
        </div>
        <a v-bind="props.presentation.header.viewer.attrs">
          {{ props.presentation.header.viewer.text }}
        </a>
      </div>
    </header>

    <div v-bind="props.presentation.content.attrs">
      <nav v-bind="props.presentation.collections.attrs">
        <a
          v-for="collection in props.presentation.collections.items"
          :key="collection.key"
          v-bind="collection.attrs"
        >
          {{ collection.label }}
          <span v-bind="collection.count.attrs">{{ collection.count.text }}</span>
        </a>
      </nav>

      <div v-bind="props.presentation.workspace.attrs">
        <div v-bind="props.presentation.master.attrs">
          <div v-bind="props.presentation.master.header.attrs">
            <p v-bind="props.presentation.master.header.label.attrs">
              {{ props.presentation.master.header.label.text }}
            </p>
            <span v-bind="props.presentation.master.header.count.attrs">
              {{ props.presentation.master.header.count.text }}
            </span>
          </div>
          <div v-bind="props.presentation.master.stream.attrs">
            <p v-bind="props.presentation.master.stream.empty.attrs">
              {{ props.presentation.master.stream.empty.text }}
            </p>
            <a
              v-for="row in props.diagnostic_rows"
              :id="row.__dom_id"
              :key="row.__dom_id"
              v-bind="row.attrs"
            >
              <div v-bind="row.header.attrs">
                <p v-bind="row.title.attrs">{{ row.title.text }}</p>
                <span v-bind="row.status.attrs">{{ row.status.text }}</span>
              </div>
              <p v-bind="row.identity.attrs">{{ row.identity.text }}</p>
            </a>
          </div>
        </div>

        <article v-bind="props.presentation.detail.attrs">
          <template v-if="props.presentation.detail.selected">
            <div v-bind="props.presentation.detail.selected.header.attrs">
              <div v-bind="props.presentation.detail.selected.header.content.attrs">
                <p v-bind="props.presentation.detail.selected.header.label.attrs">
                  {{ props.presentation.detail.selected.header.label.text }}
                </p>
                <h2 v-bind="props.presentation.detail.selected.header.title.attrs">
                  {{ props.presentation.detail.selected.header.title.text }}
                </h2>
                <p v-bind="props.presentation.detail.selected.header.identity.attrs">
                  {{ props.presentation.detail.selected.header.identity.text }}
                </p>
              </div>
              <div v-bind="props.presentation.detail.selected.header.copy.host.attrs">
                <ClipboardButton
                  v-bind="props.presentation.detail.selected.header.copy.props"
                />
              </div>
            </div>

            <dl v-bind="props.presentation.detail.selected.details.attrs">
              <div
                v-for="item in props.presentation.detail.selected.details.items"
                :key="item.key"
                v-bind="item.attrs"
              >
                <dt v-bind="item.label.attrs">{{ item.label.text }}</dt>
                <dd v-bind="item.value.attrs">{{ item.value.text }}</dd>
              </div>
            </dl>

            <nav v-bind="props.presentation.detail.selected.drilldowns.attrs">
              <a
                v-for="link in props.presentation.detail.selected.drilldowns.links"
                :key="link.key"
                v-bind="link.attrs"
              >
                {{ link.text }}
              </a>
            </nav>
          </template>
          <div
            v-else-if="props.presentation.detail.empty"
            v-bind="props.presentation.detail.empty.attrs"
          >
            {{ props.presentation.detail.empty.text }}
          </div>
        </article>
      </div>
    </div>
  </section>
</template>
