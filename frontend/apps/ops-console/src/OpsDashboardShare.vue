<script setup lang="ts">
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import CadenceOpsViewport from "@cadence/ui/CadenceOpsViewport.vue";

type RuntimeContextEntry = {
  key: string;
  value: string;
};

type DashboardShare = {
  id: string;
  eyebrow: string;
  title: string;
  restriction: {
    prefix: string;
    visibility_id: string;
    visibility: string;
    suffix: string;
  };
  context: {
    id: string;
    entries: RuntimeContextEntry[];
  };
  action: {
    id: string;
    label: string;
    href: string;
  };
};

defineProps<{ share: DashboardShare }>();
</script>

<template>
  <CadenceOpsViewport :id="share.id" class="">
    <div class="border border-primary/30 bg-base-200/30">
      <CadencePageHeading
        ><template #title>{{ share.title }}</template
        ><template #eyebrow>{{ share.eyebrow }}</template></CadencePageHeading
      >
      <p class="mt-3 text-sm text-base-content/65">
        {{ share.restriction.prefix }}
        <span :id="share.restriction.visibility_id" class="font-mono">
          {{ share.restriction.visibility }}
        </span>
        {{ share.restriction.suffix }}
      </p>
      <dl :id="share.context.id" class="mt-5 grid gap-2 text-xs sm:grid-cols-2">
        <div
          v-for="entry in share.context.entries"
          :key="entry.key"
          class="border border-base-300 bg-base-100 p-2"
        >
          <dt class="font-mono uppercase text-base-content/45">{{ entry.key }}</dt>
          <dd class="mt-1 break-all">{{ entry.value }}</dd>
        </div>
      </dl>
      <a
        :id="share.action.id"
        :href="share.action.href"
        data-phx-link="redirect"
        data-phx-link-state="push"
        class="btn btn-primary mt-6"
      >
        {{ share.action.label }}
      </a>
    </div>
  </CadenceOpsViewport>
</template>
