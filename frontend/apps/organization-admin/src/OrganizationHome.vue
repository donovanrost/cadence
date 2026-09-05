<script setup lang="ts">
import OrganizationStats from "./OrganizationStats.vue"
import RecentMissions from "./RecentMissions.vue"

type Attrs = Record<string, string>

type ElementPresentation = {
  attrs: Attrs
}

type TextPresentation = ElementPresentation & {
  text: string
}

type MissionRow = {
  id: string
  display_name: string
  slug: string
  status: "info" | "ready" | "attention"
  status_label: string
  href: string
}

type EmptyStatePresentation = {
  container: ElementPresentation
  root: ElementPresentation
  icon: ElementPresentation
  title: TextPresentation
  description: TextPresentation
  action_container: ElementPresentation
  action: TextPresentation
  action_icon: ElementPresentation
}

type Presentation = {
  root: ElementPresentation
  header: {
    attrs: Attrs
    body: ElementPresentation
    content: ElementPresentation
    title: TextPresentation
    subtitle: TextPresentation
  }
  stats: {
    mission_count: number
    spacecraft_count: number
    member_count: number
  }
  recent_missions: {
    card: ElementPresentation
    body: ElementPresentation
    header: {
      attrs: Attrs
      content: ElementPresentation
      eyebrow: TextPresentation
      title: TextPresentation
      actions: ElementPresentation
      all_missions: TextPresentation
    }
    empty_state: EmptyStatePresentation | null
    rows: MissionRow[]
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

    <OrganizationStats v-bind="props.presentation.stats" />

    <section v-bind="props.presentation.recent_missions.card.attrs">
      <div v-bind="props.presentation.recent_missions.body.attrs">
        <div v-bind="props.presentation.recent_missions.header.attrs">
          <div v-bind="props.presentation.recent_missions.header.content.attrs">
            <p v-bind="props.presentation.recent_missions.header.eyebrow.attrs">
              {{ props.presentation.recent_missions.header.eyebrow.text }}
            </p>
            <h2 v-bind="props.presentation.recent_missions.header.title.attrs">
              {{ props.presentation.recent_missions.header.title.text }}
            </h2>
          </div>
          <div v-bind="props.presentation.recent_missions.header.actions.attrs">
            <a v-bind="props.presentation.recent_missions.header.all_missions.attrs">
              {{ props.presentation.recent_missions.header.all_missions.text }}
            </a>
          </div>
        </div>

        <div
          v-if="props.presentation.recent_missions.empty_state"
          v-bind="props.presentation.recent_missions.empty_state.container.attrs"
        >
          <div v-bind="props.presentation.recent_missions.empty_state.root.attrs">
            <span v-bind="props.presentation.recent_missions.empty_state.icon.attrs"></span>
            <p v-bind="props.presentation.recent_missions.empty_state.title.attrs">
              {{ props.presentation.recent_missions.empty_state.title.text }}
            </p>
            <p v-bind="props.presentation.recent_missions.empty_state.description.attrs">
              {{ props.presentation.recent_missions.empty_state.description.text }}
            </p>
            <div v-bind="props.presentation.recent_missions.empty_state.action_container.attrs">
              <a v-bind="props.presentation.recent_missions.empty_state.action.attrs">
                <span
                  v-bind="props.presentation.recent_missions.empty_state.action_icon.attrs"
                ></span>
                {{ props.presentation.recent_missions.empty_state.action.text }}
              </a>
            </div>
          </div>
        </div>

        <RecentMissions v-else :rows="props.presentation.recent_missions.rows" />
      </div>
    </section>
  </div>
</template>
