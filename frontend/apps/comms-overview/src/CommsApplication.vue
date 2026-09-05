<script setup lang="ts">
import type { FederatedApplicationProps } from "@cadence/plugin-sdk"
import { CButton, CStatePanel } from "@cadence/ui"
import { onMounted, ref, shallowRef } from "vue"
import CommsCanonicalSurface from "./CommsCanonicalSurface.vue"
import { isCommsOverviewPresentation } from "./comms-overview"

type SurfaceId =
  | "overview"
  | "validation"
  | "transports"
  | "transport"
  | "routing"
  | "routing_detail"
  | "ground_stations"
  | "ground_station"

type SurfacePayload = {
  navigation: {
    fallback_href: string
    breadcrumbs: Array<{ label: string; href: string | null }>
  }
  data: Record<string, unknown>
}

const props = withDefaults(
  defineProps<FederatedApplicationProps & { surfaceId?: SurfaceId }>(),
  { surfaceId: undefined },
)

const surfaceId = ref<SurfaceId>(props.surfaceId ?? "overview")
const payload = shallowRef<SurfacePayload>()
const loading = ref(true)
const error = ref<string>()
let loadGeneration = 0

onMounted(() => {
  surfaceId.value = props.surfaceId ?? surfaceFromHost()
  void loadSurface()
})

async function loadSurface(): Promise<void> {
  const generation = ++loadGeneration
  loading.value = true
  error.value = undefined
  payload.value = undefined

  try {
    const response = await props.bridge.query<unknown>({
      queryId: `cadence.comms.${surfaceId.value}`,
      version: 1,
      context: props.context,
    })
    if (generation !== loadGeneration) return
    payload.value = unwrapSurfaceResponse(response, surfaceId.value)
  } catch (reason) {
    if (generation !== loadGeneration) return
    error.value = reason instanceof Error ? reason.message : "The communications surface failed."
  } finally {
    if (generation === loadGeneration) loading.value = false
  }
}

function surfaceFromHost(): SurfaceId {
  const root = document.getElementById("cadence-federation-root")
  const candidate = root?.dataset.surfaceId
  if (isSurfaceId(candidate)) return candidate

  const pathname = window.location.pathname
  if (pathname.includes("ground-stations")) return pathname.endsWith("/ground-stations") ? "ground_stations" : "ground_station"
  if (pathname.includes("transports")) return pathname.endsWith("/transports") ? "transports" : "transport"
  if (pathname.includes("routing")) return pathname.endsWith("/routing") ? "routing" : "routing_detail"
  if (pathname.endsWith("/validation")) return "validation"
  return "overview"
}

function isSurfaceId(value: string | undefined): value is SurfaceId {
  return ["overview", "validation", "transports", "transport", "routing", "routing_detail", "ground_stations", "ground_station"].includes(value ?? "")
}

function unwrapSurfaceResponse(value: unknown, requestedSurface: SurfaceId): SurfacePayload {
  if (
    requestedSurface === "overview" &&
    isRecord(value) &&
    value.queryVersion === 1 &&
    isCommsOverviewPresentation(value.presentation)
  ) {
    return {
      navigation: {
        fallback_href: `/missions/${props.context.missionId}/comms`,
        breadcrumbs: [
          { label: props.context.missionName, href: `/missions/${props.context.missionId}` },
          { label: "Comms", href: null },
        ],
      },
      data: value.presentation,
    }
  }

  if (!isRecord(value) || !isRecord(value.navigation) || !isRecord(value.data)) {
    throw new Error("The communications surface response is invalid.")
  }

  const breadcrumbs = value.navigation.breadcrumbs
  const fallbackHref = value.navigation.fallback_href
  if (!Array.isArray(breadcrumbs) || typeof fallbackHref !== "string") {
    throw new Error("The communications surface navigation is invalid.")
  }
  const safeBreadcrumbs = breadcrumbs.filter(validBreadcrumb)
  if (safeBreadcrumbs.length !== breadcrumbs.length) {
    throw new Error("The communications surface navigation is invalid.")
  }

  return {
    navigation: { fallback_href: fallbackHref, breadcrumbs: safeBreadcrumbs },
    data: value.data,
  }
}

function validBreadcrumb(value: unknown): value is { label: string; href: string | null } {
  return isRecord(value) && typeof value.label === "string" && (value.href === null || typeof value.href === "string")
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
}
</script>

<template>
  <div id="comms-application" class="comms-application">
    <CStatePanel
      v-if="loading"
      id="comms-application-loading"
      title="Loading communications surface"
      description="Requesting the mission-scoped presentation from the Phoenix host."
      tone="loading"
      aria-live="polite"
    />
    <CStatePanel
      v-else-if="error"
      id="comms-application-error"
      title="Communications surface unavailable"
      :description="error"
      tone="error"
      aria-live="polite"
    >
      <template #action>
        <CButton id="retry-comms-application" size="sm" @click="loadSurface">Retry query</CButton>
      </template>
    </CStatePanel>
    <CommsCanonicalSurface
      v-else-if="payload"
      :surface-id="surfaceId"
      :payload="payload"
    />
  </div>
</template>
