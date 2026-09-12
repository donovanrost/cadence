import type { OpsPageContext } from "@cadence/plugin-sdk/ops-pages";
import {
  bytes,
  fail,
  id,
  queryKeys,
  readCatalog,
  readPreview,
  readQuery,
  record,
  text,
  type Catalog,
  type Preview,
  type Query,
} from "../../shared/command-draft/contracts";
export type {
  Argument,
  Catalog,
  Command,
  Json,
  Preview,
  Query,
  SelectedCommand,
  Target,
} from "../../shared/command-draft/contracts";
export { previewInput, queryKeys, readPreview } from "../../shared/command-draft/contracts";
export type Receipt = {
  request_id: string;
  actor_id: string;
  requested_at: string;
  lifecycle_state: string;
};
export type Operation =
  | { status: "unconfirmed" }
  | { status: "rejected"; feedback: string }
  | { status: "completed"; receipt: Receipt };
export type AuthoringPage = {
  catalog: Catalog;
  preview: Preview | null;
  operation: Operation | null;
};
export type AuthoringPrerequisite = {
  state: "command_model_required";
  version: 1;
  context: OpsPageContext;
  actor_id: string;
};
export function readAuthoringContribution(
  value: unknown,
  context: OpsPageContext,
): AuthoringPage | AuthoringPrerequisite {
  if (record(value) && value.state === "command_model_required") {
    if (
      Object.keys(value).sort().join(",") !== "actor_id,context,state,version" ||
      value.version !== 1 ||
      !id(value.actor_id) ||
      !record(value.context) ||
      Object.keys(value.context).sort().join(",") !== "missionId,organizationId" ||
      !id(context.organizationId) ||
      !id(context.missionId) ||
      value.context.organizationId !== context.organizationId ||
      value.context.missionId !== context.missionId
    )
      return fail();
    return value as AuthoringPrerequisite;
  }
  return readAuthoringPage(value, context);
}
export type PreviewResult =
  | { status: "previewed"; preview: Preview }
  | { status: "rejected"; feedback: string };
export function authoringHref(mission: string, query: Query): string {
  if (!id(mission)) return fail();
  readQuery(query);
  const params = new URLSearchParams(
    queryKeys.flatMap((key) => (query[key] ? [[key, query[key]]] : [])),
  );
  return `/missions/${encodeURIComponent(mission)}/ops/commands/new${params.size ? `?${params}` : ""}`;
}
export function readOperation(value: unknown, preview: Preview): Operation {
  if (!record(value)) return fail();
  if (value.status === "unconfirmed") return { status: "unconfirmed" };
  if (value.status === "rejected" && text(value.feedback))
    return { status: "rejected", feedback: value.feedback };
  const r = value.receipt;
  if (
    value.status === "completed" &&
    record(r) &&
    r.request_id === preview.request_id &&
    r.actor_id === preview.actor_id &&
    r.requested_at === preview.requested_at &&
    [
      "draft",
      "validated",
      "approval_pending",
      "approved",
      "rejected",
      "queued",
      "released",
      "canceled",
    ].includes(String(r.lifecycle_state))
  )
    return { status: "completed", receipt: r as Receipt };
  return fail();
}
export function readAuthoringPage(value: unknown, context: OpsPageContext): AuthoringPage {
  if (!record(value) || bytes(JSON.stringify(value)) > 280000 || !record(value.catalog))
    return fail();
  const catalog = readCatalog(value.catalog, context);
  const preview = value.preview === null ? null : readPreview(value.preview, catalog);
  if (
    preview &&
    (preview.command_id !== catalog.query.command ||
      preview.target.id !== catalog.query.target ||
      (value.operation === null && preview.revision_id !== catalog.basis.revision_id))
  )
    return fail();
  if (value.operation !== null && !preview) return fail();
  const operation = value.operation === null ? null : readOperation(value.operation, preview!);
  return { catalog, preview, operation };
}
export function readPreviewResult(value: unknown, catalog: Catalog): PreviewResult {
  if (!record(value)) return fail();
  if (value.status === "rejected" && text(value.feedback))
    return { status: "rejected", feedback: value.feedback };
  if (value.status === "previewed") {
    const preview = readPreview(value.preview, catalog);
    if (
      preview.target.id !== catalog.query.target ||
      preview.command_id !== catalog.query.command ||
      preview.revision_id !== catalog.basis.revision_id
    )
      return fail();
    return { status: "previewed", preview };
  }
  return fail();
}
