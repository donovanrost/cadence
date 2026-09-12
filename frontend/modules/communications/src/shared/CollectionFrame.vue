<script setup lang="ts">
import { ref, watch } from "vue";
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import CadenceCard from "@cadence/ui/CadenceCard.vue";
import CadenceTableFrame from "@cadence/ui/CadenceTableFrame.vue";
import type { Collection } from "./read-contracts";
const props = defineProps<{
  id: string;
  page: Collection<{ id: string }>;
  description: string;
  createLabel: string;
}>();
const search = ref(props.page.data.query);
watch(
  () => props.page.data.query,
  (value) => (search.value = value),
);
function pageHref(page: number) {
  const query = new URLSearchParams({
    q: props.page.data.query,
    page: String(page),
    pageSize: String(props.page.data.page_size),
    sort: props.page.data.sort,
    dir: props.page.data.dir,
  });
  return props.page.navigation.fallback_href + "?" + query.toString();
}
</script>
<template>
  <section :id="id" class="space-y-6">
    <CadencePageHeading :breadcrumbs="page.navigation.breadcrumbs">
      <template #title>{{ page.data.title }}</template>
      <template #description>{{ description }}</template>
      <template #metadata
        ><span :id="id + '-count'">{{ page.data.total_count }} configured</span></template
      >
      <template #actions
        ><a
          :id="id + '-new'"
          :href="page.navigation.fallback_href + '/new'"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="btn btn-primary btn-sm"
          >{{ createLabel }}</a
        ></template
      >
    </CadencePageHeading>
    <form
      :id="id + '-search'"
      :action="page.navigation.fallback_href"
      method="get"
      class="flex gap-3 items-end"
    >
      <label class="fieldset flex-1"
        ><span class="hud-label">Search</span
        ><input
          v-model="search"
          name="q"
          type="search"
          class="input w-full"
          :id="id + '-query'"
          maxlength="240"
      /></label>
      <input name="pageSize" type="hidden" :value="page.data.page_size" />
      <input name="sort" type="hidden" :value="page.data.sort" />
      <input name="dir" type="hidden" :value="page.data.dir" />
      <button :id="id + '-search-submit'" class="btn btn-sm" type="submit">Search</button>
    </form>
    <CadenceCard class="card bg-base-200 border border-base-300" body-class="card-body p-0">
      <CadenceTableFrame :id="id + '-table'">
        <thead>
          <tr>
            <slot name="columns" />
          </tr>
        </thead>
        <tbody :id="id + '-rows'">
          <slot name="rows" />
        </tbody>
      </CadenceTableFrame>
      <p
        v-if="page.data.items.length === 0"
        :id="id + '-empty'"
        class="px-4 py-8 text-center text-sm text-base-content/70"
      >
        {{ page.data.query ? "No matches for this search." : "Nothing configured yet." }}
      </p>
      <nav
        :id="id + '-pagination'"
        aria-label="Collection pages"
        class="flex items-center justify-between gap-3 border-t border-base-300 p-4"
      >
        <a
          v-if="page.data.page > 1"
          :id="id + '-previous'"
          :href="pageHref(page.data.page - 1)"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="btn btn-sm"
          >Previous</a
        ><span v-else />
        <span class="font-mono text-xs"
          >Page {{ page.data.page }} of {{ page.data.page_count }}</span
        >
        <a
          v-if="page.data.page < page.data.page_count"
          :id="id + '-next'"
          :href="pageHref(page.data.page + 1)"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="btn btn-sm"
          >Next</a
        ><span v-else />
      </nav>
    </CadenceCard>
  </section>
</template>
