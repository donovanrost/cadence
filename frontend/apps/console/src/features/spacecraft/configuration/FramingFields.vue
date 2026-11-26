<script setup lang="ts">
import { computed, reactive, watch } from "vue";
import { isKnown } from "@/api/index.ts";
import { ApNumberField, ApSelect } from "@/ui";
import type { ConfigurationSnapshot, Protocol } from "./api.ts";
import { presetOf } from "./draft-words.ts";

/**
 * #595a (U94, mms-ux): the draft's framing. A preset fills every field; fields that match no
 * preset read "Custom". Sizes are whole bytes with the unit beside the input (U23). A field that
 * doesn't read as a number isn't applied, and `invalid` tells the bar (Save waits for it).
 */
const props = defineProps<{
  snapshot: ConfigurationSnapshot;
  protocol: Protocol | null;
  errors: Readonly<Record<string, string>>;
}>();
const emit = defineEmits<{ change: [protocol: Protocol]; invalid: [count: number] }>();

const SIZES = [
  { key: "frame_size", label: "Frame size" },
  { key: "secondary_header_length", label: "Secondary header" },
  { key: "insert_zone_length", label: "Insert zone" },
  { key: "ocf_length", label: "OCF" },
] as const;
type SizeKey = (typeof SIZES)[number]["key"];
const text = reactive<Record<SizeKey, string>>({
  frame_size: "",
  secondary_header_length: "",
  insert_zone_length: "",
  ocf_length: "",
});
const whole = (v: string) => (/^\d+$/.test(v.trim()) ? Number(v.trim()) : null);
// Discard, a save or another craft replaces the protocol: show its values (a typo that still
// reads as the same number is left as typed).
watch(
  () => props.protocol,
  (p) => {
    if (p)
      for (const s of SIZES) if (whole(text[s.key]) !== p[s.key]) text[s.key] = String(p[s.key]);
  },
  { immediate: true },
);
function setSize(key: SizeKey, v: string) {
  text[key] = v;
  const n = whole(v);
  emit("invalid", SIZES.filter((s) => whole(text[s.key]) === null).length);
  if (n !== null && props.protocol) emit("change", { ...props.protocol, [key]: n });
}

const CUSTOM = "custom";
const presetOptions = computed(() => [
  ...props.snapshot.presets.map((p) => ({ value: p.id, label: `${p.name} · v${p.version}` })),
  ...(props.protocol && presetOf(props.snapshot, props.protocol) === null
    ? [{ value: CUSTOM, label: "Custom" }]
    : []),
]);
const preset = computed(() =>
  props.protocol ? (presetOf(props.snapshot, props.protocol) ?? CUSTOM) : "",
);
function choosePreset(id: string) {
  const p = props.snapshot.presets.find((x) => x.id === id);
  if (p) emit("change", p.protocol);
}
const known = <T extends string>(v: T | { unrecognized: string }) => (isKnown(v) ? v : "");
function setLink(key: "downlink" | "uplink", v: string) {
  if (!props.protocol || v === "") return;
  if (key === "downlink" && (v === "tm" || v === "aos" || v === "uslp"))
    emit("change", { ...props.protocol, downlink: v });
  if (key === "uplink" && (v === "tc" || v === "uslp"))
    emit("change", { ...props.protocol, uplink: v });
}
const setTruncated = (v: string) =>
  props.protocol &&
  v !== "" &&
  emit("change", { ...props.protocol, truncated_primary_header: v === "yes" });
</script>

<template>
  <div class="flex flex-col gap-3">
    <ApSelect
      :model-value="preset"
      label="Framing preset"
      placeholder="Choose framing…"
      :options="presetOptions"
      @update:model-value="choosePreset"
    />
    <div v-if="protocol" class="grid grid-cols-1 gap-3 sm:grid-cols-2">
      <ApSelect
        :model-value="known(protocol.downlink)"
        label="Downlink protocol"
        :options="[
          { value: 'tm', label: 'TM' },
          { value: 'aos', label: 'AOS' },
          { value: 'uslp', label: 'USLP' },
        ]"
        :error="errors.downlink"
        @update:model-value="setLink('downlink', $event)"
      />
      <ApSelect
        :model-value="known(protocol.uplink)"
        label="Uplink protocol"
        :options="[
          { value: 'tc', label: 'TC' },
          { value: 'uslp', label: 'USLP' },
        ]"
        :error="errors.uplink"
        @update:model-value="setLink('uplink', $event)"
      />
      <ApNumberField
        v-for="s in SIZES"
        :key="s.key"
        :model-value="text[s.key]"
        :label="s.label"
        unit="bytes"
        integer
        :error="errors[s.key]"
        @update:model-value="setSize(s.key, $event)"
      />
      <ApSelect
        :model-value="protocol.truncated_primary_header ? 'yes' : 'no'"
        label="Truncated primary header"
        :options="[
          { value: 'yes', label: 'Yes' },
          { value: 'no', label: 'No' },
        ]"
        :error="errors.truncated_primary_header"
        @update:model-value="setTruncated"
      />
    </div>
  </div>
</template>
