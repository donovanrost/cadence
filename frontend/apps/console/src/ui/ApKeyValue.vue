<script setup lang="ts">
/** Definition list of facts. Values may be overridden per key with `#value-<key>` slots. */
export type ApKeyValueItem = Readonly<{
  key: string;
  label: string;
  value: string;
  mono?: boolean;
}>;
defineProps<{ items: readonly ApKeyValueItem[]; columns?: 1 | 2 }>();
</script>

<template>
  <dl class="m-0 grid gap-x-6 gap-y-3" :class="columns === 2 ? 'grid-cols-2' : 'grid-cols-1'">
    <div v-for="item in items" :key="item.key" class="flex min-w-0 flex-col gap-1">
      <dt class="ap-label">{{ item.label }}</dt>
      <dd class="m-0 text-md text-text-2" :class="item.mono ? 'font-mono' : ''">
        <slot :name="`value-${item.key}`">{{ item.value }}</slot>
      </dd>
    </div>
  </dl>
</template>
