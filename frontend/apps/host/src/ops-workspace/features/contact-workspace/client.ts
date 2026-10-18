import { QueryClient, queryOptions } from "@tanstack/vue-query";
import { ref, readonly, type InjectionKey } from "vue";
import {
  admitContactRecord,
  createContactScheduleService,
  type ContactSchedule,
  type ContactRecord,
  type ContactRecordPort,
  type ScheduleWireRequest,
} from "@cadence/planning-and-contacts/contact-scheduling";
import { record } from "../../../shell/snapshot-readers";
import type { WorkspaceBootstrap } from "./contracts";

export class WorkspaceRequestError extends Error {
  constructor(readonly status: number) {
    super(status === 404 ? "This contact is unavailable." : "Contact data could not be refreshed.");
  }
}
type WorkspacePage =
  | { kind: "schedule"; model: ContactSchedule }
  | { kind: "record"; model: ContactRecord };

export function createWorkspaceClient(bootstrap: WorkspaceBootstrap, queries: QueryClient) {
  const { actorId, organizationId, missionId } = bootstrap;
  const context = { organization_id: organizationId, mission_id: missionId };
  const prefix = ["contact-workspace", actorId, organizationId, missionId] as const;
  const api = `/api/cadence/contact-workspace/v1/missions/${encodeURIComponent(missionId)}`;
  const sessionChanged = ref(false);

  async function request(path: string, options: RequestInit = {}): Promise<unknown> {
    if (sessionChanged.value) throw new WorkspaceRequestError(409);
    const controller = new AbortController();
    const abort = () => controller.abort();
    if (options.signal?.aborted) abort();
    options.signal?.addEventListener("abort", abort, { once: true });
    const timeout = setTimeout(abort, 15_000);
    try {
      const response = await fetch(api + path, {
        ...options,
        signal: controller.signal,
        credentials: "same-origin",
        cache: "no-store",
        headers: {
          Accept: "application/json",
          "Content-Type": "application/json",
          "x-csrf-token": bootstrap.context.csrf_token,
          "x-cadence-workspace-user": actorId,
          "x-cadence-workspace-organization": organizationId,
        },
      });
      if (
        sessionChanged.value ||
        response.redirected ||
        [401, 403, 409].includes(response.status)
      ) {
        sessionChanged.value = true;
        queries.clear();
        throw new WorkspaceRequestError(409);
      }
      if (!response.ok) throw new WorkspaceRequestError(response.status);
      const value: unknown = await response.json();
      if (
        !record(value) ||
        value.version !== 1 ||
        value.actor_id !== actorId ||
        value.organization_id !== organizationId ||
        value.mission_id !== missionId
      )
        throw Error("Unverified contact response");
      return value.data;
    } finally {
      clearTimeout(timeout);
      options.signal?.removeEventListener("abort", abort);
    }
  }

  function scheduleService(search: string) {
    return createContactScheduleService(
      {
        async read() {
          const page = await queries.fetchQuery({ ...pageOptions(null, search), staleTime: 0 });
          if (page.kind !== "schedule") throw Error("Different contact resource");
          return page.model;
        },
        async execute(...[action, input]: ScheduleWireRequest) {
          const result = await request(`/actions/${action}`, {
            method: "POST",
            body: JSON.stringify(input),
          });
          // Invalidation marks all related ledgers stale; active observers refetch.
          // An unavailable refresh cannot change a mutation's recorded outcome.
          if (action !== "search") queries.invalidateQueries({ queryKey: prefix }).catch(() => {});
          return result;
        },
      },
      context,
      actorId,
    );
  }

  function matchesQuery(query: Readonly<Record<string, unknown>>, search: string) {
    for (const [key, value] of new URLSearchParams(search)) {
      const expected = typeof query[key] === "number" ? Number(value) : value.trim();
      if (query[key] !== expected) throw Error("Different contact query");
    }
  }

  function pageOptions(id: string | null, search: string) {
    return queryOptions({
      queryKey: [...prefix, id ? "record" : "schedule", id, search],
      async queryFn({ signal }): Promise<WorkspacePage> {
        if (id) {
          const data = await request(`/records/${encodeURIComponent(id)}${search}`, { signal });
          const model =
            record(data) && admitContactRecord(data.record, { ...context, contact_id: id });
          if (!model || model.subject.id !== id) throw Error("Unavailable contact record");
          matchesQuery(model.query, search);
          return { kind: "record", model };
        }
        const data = await request(`/schedule${search}`, { signal });
        if (!record(data)) throw Error("Unavailable contact schedule");
        const model = scheduleService(search).admit(data.schedule).model;
        matchesQuery(model.query, search);
        return { kind: "schedule", model };
      },
    });
  }

  function recordPort(id: string, search: string): ContactRecordPort {
    return {
      protocol: "remote-query",
      context: { ...context, contact_id: id },
      async refresh() {
        const page = await queries.fetchQuery({ ...pageOptions(id, search), staleTime: 0 });
        if (page.kind !== "record") throw Error("Different contact resource");
        return page.model;
      },
    };
  }
  return { sessionChanged: readonly(sessionChanged), pageOptions, scheduleService, recordPort };
}
export type WorkspaceClient = ReturnType<typeof createWorkspaceClient>;
export const workspaceClientKey: InjectionKey<WorkspaceClient> = Symbol("contact-workspace-client");

export function createWorkspaceQueryClient() {
  return new QueryClient({
    defaultOptions: {
      queries: {
        staleTime: 15_000,
        gcTime: 300_000,
        retry: false,
        refetchOnMount: "always",
        refetchOnWindowFocus: true,
        refetchOnReconnect: true,
        refetchInterval: 5_000,
        refetchIntervalInBackground: false,
      },
      mutations: { retry: false },
    },
  });
}
