import {defineComponent, h} from "vue"
import {createLiveVue, findComponent} from "live_vue"

const components = import.meta.glob("./vue/**/*.vue", {eager: true})

type Surface = {
  applicationKey: string
  surfaceId: string
  missionId: string
  spacecraftId?: string
}

function surfaceForPath(pathname: string): Surface | undefined {
  const parts = pathname.split("/").filter(Boolean)
  if (parts[0] !== "missions" || !parts[1]) return undefined

  const missionId = parts[1]
  const rest = parts.slice(2)

  if (rest[0] === "catalog") {
    const surfaceId =
      rest[1] === "new"
        ? "catalog_database_new"
        : rest[1] === "databases"
          ? "catalog_database_show"
          : rest[1] === "revisions"
            ? "catalog_revision_show"
            : rest[1] === "artifacts"
              ? "catalog_artifact_show"
              : rest[1] === "imports"
                ? "catalog_import_run_show"
                : "catalog_index"

    return {applicationKey: "mission_catalog", surfaceId, missionId}
  }

  if (rest[0] === "new") {
    return {applicationKey: "mission_catalog", surfaceId: "mission_new", missionId}
  }

  if (rest[0] === "applications") {
    return {
      applicationKey: "mission_catalog",
      surfaceId: rest.length > 1 ? "mission_applications" : "mission_applications",
      missionId
    }
  }

  if (rest[0] === "spacecraft") {
    if (!rest[1]) return {applicationKey: "spacecraft", surfaceId: "list", missionId}
    if (rest[1] === "new") return {applicationKey: "spacecraft", surfaceId: "new", missionId}
    if (rest[1] === "profiles") {
      const surfaceId =
        rest[2] === "new" ? "profile_new" : rest[2] ? "profile_show" : "profile_list"
      return {applicationKey: "spacecraft", surfaceId, missionId}
    }

    const spacecraftId = rest[1]
    const surfaceId =
      rest[2] === "identity" || rest[2] === "edit"
        ? "edit"
        : rest[2] || "show"
    return {applicationKey: "spacecraft", surfaceId, missionId, spacecraftId}
  }

  if (rest[0] === "comms") {
    const surfaceId =
      rest[1] === "transports"
        ? rest[2] === "new"
          ? "transport_new"
          : rest[2]
            ? "transport_show"
            : "transport_list"
        : rest[1] === "ground-stations"
          ? rest[2] === "new" || rest[3] === "edit"
            ? "ground_station_form"
            : rest[2]
              ? "ground_station_show"
              : "ground_station_list"
          : rest[1] === "routing"
            ? rest[2] === "new"
              ? "routing_new"
              : rest[2]
                ? "routing_show"
                : "routing_list"
            : rest[1] === "validation"
              ? "validation"
              : rest[1] === "providers"
                ? rest[2] === "new"
                  ? "provider_new"
                  : rest[2]
                    ? "provider_show"
                    : "provider_list"
                : "overview"

    return {applicationKey: "comms", surfaceId, missionId}
  }

  if (rest[0] === "ops") {
    return {applicationKey: "ops_console", surfaceId: "ops", missionId}
  }

  if (rest.length === 0) return {applicationKey: "mission_catalog", surfaceId: "mission_overview", missionId}
  return {applicationKey: "mission_catalog", surfaceId: "mission_overview", missionId}
}

const FederatedFullPageSurface = defineComponent({
  name: "FederatedFullPageSurface",
  inheritAttrs: false,
  setup(_props, {attrs}) {
    return () => {
      const surface = surfaceForPath(globalThis.location?.pathname ?? "")
      const href = `${globalThis.location?.pathname ?? ""}${globalThis.location?.search ?? ""}`

      if (!surface) return h("div", {...attrs, id: "cadence-federation-root"})

      return h("div", {
        ...attrs,
        id: "cadence-federation-root",
        "data-mission-id": surface.missionId,
        "data-spacecraft-id": surface.spacecraftId,
        "data-host-scope": surface.spacecraftId ? "spacecraft" : "mission",
        "data-application-key": surface.applicationKey,
        "data-surface-id": surface.surfaceId,
        "data-catalog-url": "/api/cadence/application-host/v1/catalog",
        "data-fallback-href": href
      })
    }
  }
})

export default createLiveVue({
  resolve: (name) =>
    name === "FederatedFullPageSurface"
      ? FederatedFullPageSurface
      : findComponent(components, name)
})
