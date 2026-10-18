<script setup lang="ts">
import type { WidgetRowsPresentation } from "./WidgetRows.contracts";

import WidgetDataLinks from "./WidgetDataLinks.vue";

defineProps<{ presentation: WidgetRowsPresentation }>();
</script>

<template>
  <table
    v-if="presentation.kind === 'status_matrix' || presentation.kind === 'data_table'"
    :class="presentation.root.class"
  >
    <thead :class="presentation.head.class">
      <tr :class="presentation.head.row_class">
        <th v-for="heading in presentation.head.cells" :key="heading.key" :class="heading.class">
          <span v-if="heading.text_class" :class="heading.text_class">{{ heading.text }}</span>
          <template v-else>{{ heading.text }}</template>
        </th>
      </tr>
    </thead>
    <tbody>
      <tr v-for="row in presentation.rows" :key="row.key" :class="row.class" v-bind="row.attrs">
        <td v-for="cell in row.cells" :key="cell.key" :class="cell.class" v-bind="cell.attrs">
          <template v-if="cell.text !== null">{{ cell.text }}</template>
          <component
            :is="badge.tag"
            v-for="(badge, badgeIndex) in cell.badges"
            :key="badge.key || `${cell.key}-badge-${badgeIndex}`"
            :class="badge.class"
            v-bind="badge.attrs"
            >{{ badge.text }}</component
          >
          <WidgetDataLinks v-if="cell.link_menu" :presentation="cell.link_menu" />
        </td>
      </tr>
    </tbody>
  </table>

  <div v-else-if="presentation.kind === 'state_timeline'" :class="presentation.root.class">
    <div v-for="lane in presentation.lanes" :key="lane.key" :class="lane.class" v-bind="lane.attrs">
      <div :class="lane.heading.class">
        <div :class="lane.heading.label_container_class">
          <div :class="lane.heading.label.class" v-bind="lane.heading.label.attrs">
            {{ lane.heading.label.text }}
          </div>
          <div :class="lane.heading.metadata_class">
            <span
              v-for="(item, itemIndex) in lane.heading.metadata"
              :key="`${lane.key}-metadata-${itemIndex}`"
              >{{ item }}</span
            >
          </div>
        </div>
        <span :class="lane.heading.count.class">{{ lane.heading.count.text }}</span>
      </div>
      <div :class="lane.rows_class">
        <div v-for="row in lane.rows" :key="row.key" :class="row.class" v-bind="row.attrs">
          <div :class="row.content_class">
            <div :class="row.heading_class">
              <span :class="row.title.class">{{ row.title.text }}</span>
              <component
                :is="badge.tag"
                v-for="(badge, badgeIndex) in row.badges"
                :key="badge.key || `${row.key}-badge-${badgeIndex}`"
                :class="badge.class"
                v-bind="badge.attrs"
                >{{ badge.text }}</component
              >
            </div>
            <div :class="row.bar.class">
              <div :class="row.bar.fill_class"></div>
            </div>
            <div :class="row.metadata_class">
              <span
                v-for="(item, itemIndex) in row.metadata"
                :key="`${row.key}-metadata-${itemIndex}`"
                >{{ item }}</span
              >
            </div>
          </div>
          <div :class="row.actions_class">
            <WidgetDataLinks v-if="row.link_menu" :presentation="row.link_menu" />
          </div>
        </div>
      </div>
    </div>
  </div>

  <div v-else-if="presentation.kind === 'event_timeline'" :class="presentation.root.class">
    <div v-for="row in presentation.rows" :key="row.key" :class="row.class" v-bind="row.attrs">
      <div :class="row.marker.container_class">
        <span :class="row.marker.class"></span>
      </div>
      <div :class="row.content_class">
        <div :class="row.heading_class">
          <span :class="row.category.class">{{ row.category.text }}</span>
          <component
            :is="badge.tag"
            v-for="(badge, badgeIndex) in row.badges"
            :key="badge.key || `${row.key}-badge-${badgeIndex}`"
            :class="badge.class"
            v-bind="badge.attrs"
            >{{ badge.text }}</component
          >
          <span :class="row.time.class">{{ row.time.text }}</span>
        </div>
        <div :class="row.title.class" v-bind="row.title.attrs">{{ row.title.text }}</div>
        <div :class="row.metadata_class">
          <span
            v-for="(item, itemIndex) in row.metadata"
            :key="`${row.key}-metadata-${itemIndex}`"
            >{{ item }}</span
          >
        </div>
      </div>
      <div :class="row.actions_class">
        <WidgetDataLinks v-if="row.link_menu" :presentation="row.link_menu" />
      </div>
    </div>
  </div>
</template>
