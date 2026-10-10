import {
  inject,
  onBeforeUnmount,
  toValue,
  watchEffect,
  type InjectionKey,
  type MaybeRefOrGetter,
} from "vue";
import type { IconName } from "@cadence/ui/icons";
import type { Tone } from "@cadence/ui/tones";
import {
  isRouteId,
  type Href,
  type RouteHeaderKind,
  type RouteId,
  type RouteLayer,
} from "./routes";

/**
 * Pages describe their header as data; the host draws it. There is no markup
 * slot, so a page cannot add an eyebrow, style a button or render its own title.
 */
type ActionBase = { id: string; label: string; icon?: IconName; disabled?: boolean };
export type LinkAction = ActionBase & { href: Href };
export type CommandAction = ActionBase & { run: () => void | Promise<void> };
/** Menu entries; only these may be destructive. */
export type MenuItem = (LinkAction | CommandAction) & { tone?: "danger" };
export type MenuAction = ActionBase & { menu: readonly MenuItem[] };
export type PageAction = LinkAction | CommandAction | MenuAction;

type UpTo2<T> = readonly [] | readonly [T] | readonly [T, T];
type UpTo3<T> = UpTo2<T> | readonly [T, T, T];
export type HeaderStatus = { tone: Tone; label: string };

type Shared = {
  /** One sentence; replaces the route's default description. */
  description?: string;
  /** Short facts after the title, e.g. "14 open". */
  facts?: readonly string[];
  /** The single solid button. */
  primary?: PageAction;
  more?: readonly MenuItem[];
};
/** Collection pages take their title from the route catalog. */
type Untitled = { title?: never; status?: never };

/** Ops pages: operators' live, action-oriented work. */
type OpsBase = Shared & {
  /** Quiet buttons; a fourth does not compile. Overflow goes in `more`. */
  actions?: UpTo3<PageAction>;
  /** The standard refresh affordance for pages that do not update live. */
  refresh?: { run: () => void | Promise<void>; pending?: boolean };
  identifier?: never;
};
export type OpsCollectionHeader = OpsBase & Untitled;
/** Resource pages must name the resource they show. */
export type OpsResourceHeader = OpsBase & { title: string; status?: HeaderStatus };

/** Management pages: records maintained through forms. */
type ManagementBase = Shared & {
  /** Quiet buttons; a third does not compile. Overflow goes in `more`. */
  actions?: UpTo2<PageAction>;
  /** Records hold no live state worth a refresh; the browser reloads them. */
  refresh?: never;
};
export type ManagementCollectionHeader = ManagementBase & Untitled & { identifier?: never };
export type ManagementResourceHeader = ManagementBase & {
  title: string;
  /** The record's stable id, shown beside its name. */
  identifier?: string;
  status?: HeaderStatus;
};

export type OpsRoute = { [R in RouteId]: RouteLayer<R> extends "ops" ? R : never }[RouteId];
export type ManagementRoute = Exclude<RouteId, OpsRoute>;
type ByKind<R extends RouteId, Collection, Resource> =
  RouteHeaderKind<R> extends "resource"
    ? Resource
    : RouteHeaderKind<R> extends "collection"
      ? Collection
      : never;
/** The header an Ops route admits; routes with `none` own their identity bar. */
export type OpsHeaderFor<R extends OpsRoute> = ByKind<R, OpsCollectionHeader, OpsResourceHeader>;
export type ManagementHeaderFor<R extends ManagementRoute> = ByKind<
  R,
  ManagementCollectionHeader,
  ManagementResourceHeader
>;
export type PageHeader =
  | OpsCollectionHeader
  | OpsResourceHeader
  | ManagementCollectionHeader
  | ManagementResourceHeader;

export type PageHeaderHost = {
  /** The catalog route the host has mounted. */
  route(): string;
  claim(owner: symbol, routes: readonly string[]): void;
  update(owner: symbol, header: unknown): void;
  release(owner: symbol): void;
};
// Stable across independently built federated modules.
export const pageHeaderKey = Symbol.for("cadence.page-header.v1") as InjectionKey<PageHeaderHost>;

/** One header per route a component serves, each checked against that route's policy. */
export type OpsHeaders = { readonly [R in OpsRoute]?: MaybeRefOrGetter<OpsHeaderFor<R>> };
export type ManagementHeaders = {
  readonly [R in ManagementRoute]?: MaybeRefOrGetter<ManagementHeaderFor<R>>;
};

function describe(headers: Partial<Record<RouteId, MaybeRefOrGetter<unknown>>>): void {
  const host = inject(pageHeaderKey, null);
  if (!host) return;
  const owner = Symbol("page-header");
  host.claim(owner, Object.keys(headers));
  const mounted = host.route();
  const entry = isRouteId(mounted) ? headers[mounted] : undefined;
  if (entry !== undefined) watchEffect(() => host.update(owner, toValue(entry)));
  onBeforeUnmount(() => host.release(owner));
}

/**
 * Describe an Ops page's header for every route it serves; the host applies the
 * entry for the route it mounted. Call once, from the routed page's root.
 */
export function useOpsHeaders(headers: OpsHeaders): void {
  describe(headers);
}

/** Describe the header of an Ops page that serves exactly one route. */
export function useOpsHeader<R extends OpsRoute>(
  route: R,
  header: MaybeRefOrGetter<OpsHeaderFor<R>>,
): void {
  describe({ [route]: header });
}

/** Describe a management page's header for every route it serves. */
export function useManagementHeaders(headers: ManagementHeaders): void {
  describe(headers);
}

/** Describe the header of a management page that serves exactly one route. */
export function useManagementHeader<R extends ManagementRoute>(
  route: R,
  header: MaybeRefOrGetter<ManagementHeaderFor<R>>,
): void {
  describe({ [route]: header });
}
