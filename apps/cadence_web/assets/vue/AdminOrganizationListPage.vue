<script setup lang="ts">
import AdminOrganizationList from "./AdminOrganizationList.vue"

type RawAttrs = Record<string, string>

type ElementPresentation = {
  attrs: RawAttrs
}

type TextPresentation = ElementPresentation & {
  text: string
}

type OrganizationRow = {
  id: string
  display_name: string
  slug: string
  href: string
}

type BreadcrumbItem = {
  separator: TextPresentation | null
  kind: "link" | "current"
  content: TextPresentation
}

type AdminOrganizationListPresentation = {
  root: ElementPresentation
  header: {
    root: ElementPresentation
    layout: ElementPresentation
    content: ElementPresentation
    breadcrumbs: {
      root: ElementPresentation
      items: BreadcrumbItem[]
    }
    title: TextPresentation
    actions: ElementPresentation
    create_action: TextPresentation
  }
  empty_state: {
    root: ElementPresentation
    title: TextPresentation
    description: TextPresentation
    action_container: ElementPresentation
    action: TextPresentation
    action_icon: ElementPresentation
  } | null
  card: {
    root: ElementPresentation
    body: ElementPresentation
    child: ElementPresentation
    rows: OrganizationRow[]
  } | null
}

defineProps<{presentation: AdminOrganizationListPresentation}>()
</script>

<template>
  <div v-bind="presentation.root.attrs">
    <header v-bind="presentation.header.root.attrs">
      <div v-bind="presentation.header.layout.attrs">
        <div v-bind="presentation.header.content.attrs">
          <nav v-bind="presentation.header.breadcrumbs.root.attrs">
            <template
              v-for="breadcrumb in presentation.header.breadcrumbs.items"
              :key="breadcrumb.content.text"
            >
              <span v-if="breadcrumb.separator" v-bind="breadcrumb.separator.attrs">
                {{ breadcrumb.separator.text }}
              </span>
              <a v-if="breadcrumb.kind === 'link'" v-bind="breadcrumb.content.attrs">
                {{ breadcrumb.content.text }}
              </a>
              <span v-else v-bind="breadcrumb.content.attrs">
                {{ breadcrumb.content.text }}
              </span>
            </template>
          </nav>
          <h1 v-bind="presentation.header.title.attrs">
            {{ presentation.header.title.text }}
          </h1>
        </div>
        <div v-bind="presentation.header.actions.attrs">
          <a v-bind="presentation.header.create_action.attrs">
            {{ presentation.header.create_action.text }}
          </a>
        </div>
      </div>
    </header>

    <div v-if="presentation.empty_state" v-bind="presentation.empty_state.root.attrs">
      <p v-bind="presentation.empty_state.title.attrs">
        {{ presentation.empty_state.title.text }}
      </p>
      <p v-bind="presentation.empty_state.description.attrs">
        {{ presentation.empty_state.description.text }}
      </p>
      <div v-bind="presentation.empty_state.action_container.attrs">
        <a v-bind="presentation.empty_state.action.attrs">
          <span v-bind="presentation.empty_state.action_icon.attrs"></span>
          {{ presentation.empty_state.action.text }}
        </a>
      </div>
    </div>

    <section v-if="presentation.card" v-bind="presentation.card.root.attrs">
      <div v-bind="presentation.card.body.attrs">
        <div v-bind="presentation.card.child.attrs">
          <AdminOrganizationList :rows="presentation.card.rows" />
        </div>
      </div>
    </section>
  </div>
</template>
