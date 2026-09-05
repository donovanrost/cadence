<script setup>
import CsvDownloadButton from "./CsvDownloadButton.vue";

const props = defineProps({
  presentation: { type: Object, required: true },
});
</script>

<template>
  <section v-bind="props.presentation.root.attrs">
    <p v-if="props.presentation.state === 'missing'" :class="props.presentation.missing.class">
      {{ props.presentation.missing.text }}
    </p>

    <template v-else>
      <div :class="props.presentation.header.class">
        <div :class="props.presentation.header.badges_class">
          <span :class="props.presentation.header.type_badge.class">
            {{ props.presentation.header.type_badge.text }}
          </span>
          <span
            :class="props.presentation.header.series_badge.class"
            v-bind="props.presentation.header.series_badge.attrs"
            >{{ props.presentation.header.series_badge.text }}</span
          >
          <span
            :class="props.presentation.header.rows_badge.class"
            v-bind="props.presentation.header.rows_badge.attrs"
            >{{ props.presentation.header.rows_badge.text }}</span
          >
        </div>
        <p
          v-if="props.presentation.header.time_range"
          :class="props.presentation.header.time_range.class"
        >
          {{ props.presentation.header.time_range.text }}
        </p>
        <p
          v-if="props.presentation.header.capped"
          :id="props.presentation.header.capped.id"
          :class="props.presentation.header.capped.class"
        >
          {{ props.presentation.header.capped.text }}
        </p>
      </div>

      <div :id="props.presentation.download.host.id">
        <CsvDownloadButton v-bind="props.presentation.download.props" />
      </div>

      <section :class="props.presentation.stats.class" v-bind="props.presentation.stats.attrs">
        <h3 :class="props.presentation.stats.heading.class">
          {{ props.presentation.stats.heading.text }}
        </h3>
        <div
          v-for="(stat, statIndex) in props.presentation.stats.rows"
          :key="statIndex"
          :class="stat.class"
          v-bind="stat.attrs"
        >
          <span :class="stat.label.class" :title="stat.label.title">
            {{ stat.label.text
            }}<span v-if="stat.label.unit" :class="stat.label.unit_class">{{
              stat.label.unit
            }}</span>
          </span>
          <span v-for="value in stat.values" :key="value.label.text" :class="value.class">
            <span :class="value.label.class">{{ value.label.text }}</span>
            <span :class="value.value.class">{{ value.value.text }}</span>
          </span>
        </div>
        <p
          v-if="props.presentation.stats.empty.visible"
          :class="props.presentation.stats.empty.class"
        >
          {{ props.presentation.stats.empty.text }}
        </p>
      </section>

      <section :class="props.presentation.table.class" v-bind="props.presentation.table.attrs">
        <h3 :class="props.presentation.table.heading.class">
          {{ props.presentation.table.heading.text }}
        </h3>
        <div :class="props.presentation.table.scroll_class">
          <table :class="props.presentation.table.table_class">
            <thead>
              <tr>
                <th :class="props.presentation.table.time_header.class">
                  {{ props.presentation.table.time_header.text }}
                </th>
                <th
                  v-for="(series, seriesIndex) in props.presentation.table.series_headers"
                  :key="seriesIndex"
                  :class="series.class"
                >
                  {{ series.text
                  }}<span v-if="series.unit" :class="series.unit_class">{{ series.unit }}</span>
                </th>
              </tr>
            </thead>
            <tbody>
              <tr v-if="props.presentation.table.empty.visible">
                <td
                  :colspan="props.presentation.table.empty.colspan"
                  :class="props.presentation.table.empty.class"
                >
                  {{ props.presentation.table.empty.text }}
                </td>
              </tr>
              <tr v-for="(row, rowIndex) in props.presentation.table.rows" :key="rowIndex">
                <td :class="row.timestamp.class">{{ row.timestamp.text }}</td>
                <td
                  v-for="(value, valueIndex) in row.values"
                  :key="valueIndex"
                  :class="value.class"
                >
                  {{ value.text }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </template>
  </section>
</template>
