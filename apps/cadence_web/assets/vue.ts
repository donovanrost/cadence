import {defineComponent, h} from "vue"
import {createLiveVue, findComponent} from "live_vue"

const components = import.meta.glob("./vue/**/*.vue", {eager: true})

type Surface = {
  applicationKey: string
  surfaceId: string
  hostScope: "organization" | "user" | "admin" | "mission" | "spacecraft"
  organizationId?: string
  userId?: string
  missionId?: string
  spacecraftId?: string
}

function surfaceForPath(pathname: string): Surface | undefined {
  const parts = pathname.split("/").filter(Boolean)

  if (parts[0] === "notifications") {
    return {applicationKey: "organization_admin", surfaceId: "notifications", hostScope: "user"}
  }

  if (parts[0] === "provider-accounts") {
    const surfaceId = parts[1] === "new" ? "provider_account_new" : parts[1] ? "provider_account_show" : "provider_accounts"
    return {applicationKey: "organization_admin", surfaceId, hostScope: "organization"}
  }

  if (parts[0] === "admin") {
    const surfaceId =
      parts[1] === "runtime"
        ? "admin_runtime"
        : parts[1] !== "organizations"
          ? "admin_home"
          : parts[2] === "new"
            ? "admin_organization_new"
            : parts[2] && parts[3] === "invite"
              ? "admin_organization_invite"
              : parts[2]
                ? "admin_organization_show"
                : "admin_organizations"

    return {applicationKey: "organization_admin", surfaceId, hostScope: "admin"}
  }

  if (parts.length === 0) {
    return {applicationKey: "organization_admin", surfaceId: "organization_home", hostScope: "organization"}
  }

  if (parts[0] === "missions" && !parts[1]) {
    return {applicationKey: "mission_catalog", surfaceId: "mission_list", hostScope: "organization"}
  }

  if (parts[0] === "missions" && parts[1] === "new") {
    return {applicationKey: "mission_catalog", surfaceId: "mission_new", hostScope: "organization"}
  }

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

    return {applicationKey: "mission_catalog", surfaceId, hostScope: "mission", missionId}
  }

  if (rest[0] === "new") {
    return {applicationKey: "mission_catalog", surfaceId: "mission_new", hostScope: "mission", missionId}
  }

  if (rest[0] === "applications") {
    return {
      applicationKey: "mission_catalog",
      surfaceId: "mission_applications",
      hostScope: "mission",
      missionId
    }
  }

  if (rest[0] === "spacecraft") {
    if (!rest[1]) return {applicationKey: "spacecraft", surfaceId: "list", hostScope: "mission", missionId}
    if (rest[1] === "new") return {applicationKey: "spacecraft", surfaceId: "new", hostScope: "mission", missionId}
    if (rest[1] === "profiles") {
      const surfaceId =
        rest[2] === "new" ? "profile_new" : rest[2] ? "profile_show" : "profile_list"
      return {applicationKey: "spacecraft", surfaceId, hostScope: "mission", missionId}
    }

    const spacecraftId = rest[1]
    const surfaceId =
      rest[2] === "identity" || rest[2] === "edit"
        ? "edit"
        : rest[2] || "show"
    return {applicationKey: "spacecraft", surfaceId, hostScope: "spacecraft", missionId, spacecraftId}
  }

  if (rest[0] === "comms") {
    const surfaceId =
      rest[1] === "transports"
        ? rest[2] === "new"
          ? "transport"
          : rest[2]
            ? "transport"
            : "transports"
        : rest[1] === "ground-stations"
          ? rest[2] === "new" || rest[3] === "edit"
            ? "ground_station"
            : rest[2]
              ? "ground_station"
              : "ground_stations"
          : rest[1] === "routing"
            ? rest[2] === "new"
              ? "routing"
              : rest[2]
                ? "routing_detail"
                : "routing"
            : rest[1] === "validation"
              ? "validation"
              : rest[1] === "providers"
                ? rest[2] === "new"
                  ? "provider_new"
                  : rest[2]
                    ? "provider_show"
                    : "provider_list"
                : "overview"

    return {applicationKey: "comms", surfaceId, hostScope: "mission", missionId}
  }

  if (rest[0] === "ops") {
    return {applicationKey: "ops_console", surfaceId: "ops", hostScope: "mission", missionId}
  }

  return {applicationKey: "mission_catalog", surfaceId: "mission_overview", hostScope: "mission", missionId}
}

type SurfaceProps = {
  applicationKey?: string
  surfaceId?: string
  hostScope?: Surface["hostScope"]
  organizationId?: string
  userId?: string
  missionId?: string
  spacecraftId?: string
  application_key?: string
  surface_id?: string
  host_scope?: Surface["hostScope"]
  organization_id?: string
  user_id?: string
  mission_id?: string
  spacecraft_id?: string
}

const FederatedFullPageSurface = defineComponent({
  name: "FederatedFullPageSurface",
  inheritAttrs: false,
  props: {
    applicationKey: String,
    surfaceId: String,
    hostScope: String,
    organizationId: String,
    userId: String,
    missionId: String,
    spacecraftId: String,
    application_key: String,
    surface_id: String,
    host_scope: String,
    organization_id: String,
    user_id: String,
    mission_id: String,
    spacecraft_id: String
  },
  setup(props: SurfaceProps, {attrs}) {
    return () => {
      const inferred = surfaceForPath(globalThis.location?.pathname ?? "")
      const applicationKey = props.applicationKey ?? props.application_key ?? inferred?.applicationKey
      const surfaceId = props.surfaceId ?? props.surface_id ?? inferred?.surfaceId
      const hostScope = props.hostScope ?? props.host_scope ?? inferred?.hostScope
      const organizationId = props.organizationId ?? props.organization_id ?? inferred?.organizationId
      const userId = props.userId ?? props.user_id ?? inferred?.userId
      const missionId = props.missionId ?? props.mission_id ?? inferred?.missionId
      const spacecraftId = props.spacecraftId ?? props.spacecraft_id ?? inferred?.spacecraftId
      const href = `${globalThis.location?.pathname ?? ""}${globalThis.location?.search ?? ""}`

      if (!applicationKey || !surfaceId || (!hostScope && !missionId)) {
        return h("div", {...attrs, id: "cadence-federation-root"})
      }

      const resolvedHostScope = hostScope ?? (spacecraftId ? "spacecraft" : "mission")

      return h("div", {
        ...attrs,
        id: "cadence-federation-root",
        "data-organization-id": organizationId,
        "data-user-id": userId,
        "data-mission-id": missionId,
        "data-spacecraft-id": spacecraftId,
        "data-host-scope": resolvedHostScope,
        "data-application-key": applicationKey,
        "data-surface-id": surfaceId,
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
