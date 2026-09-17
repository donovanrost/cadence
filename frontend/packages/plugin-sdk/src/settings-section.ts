/** Settings placement metadata. Registration does not grant read or write authority. */
export const SETTINGS_SECTION_SLOT = "settings.section" as const;
export type SettingsScope = "organization" | "mission";
export type SettingsSectionOwner =
  | Readonly<{ kind: "host"; label: string }>
  | Readonly<{ kind: "application"; applicationKey: string; label: string }>;

export type SettingsSectionDefinition = Readonly<{
  id: string;
  slot: typeof SETTINGS_SECTION_SLOT;
  version: 1;
  scopes: readonly SettingsScope[];
  title: string;
  description: string;
  owner: SettingsSectionOwner;
}>;

export type SettingsContext = Readonly<{
  actorId: string;
  organizationId: string;
  organizationName: string;
}> &
  (
    | Readonly<{ scope: "organization"; missionId: null; missionName: null }>
    | Readonly<{ scope: "mission"; missionId: string; missionName: string }>
  );
export type SettingsSource = "organization" | "inherited" | "overridden" | "enforced";
export type SettingsSnapshot<T> = Readonly<{
  token: string;
  version: number;
  saved: T | null;
  effective: T;
  organizationDefault: T;
  allowOverride: boolean;
  source: SettingsSource;
}>;
export type SettingsWriteResult =
  | Readonly<{ status: "saved"; revisionId: string; snapshot: unknown }>
  | Readonly<{ status: "rejected"; message: string }>
  | Readonly<{ status: "unconfirmed" }>;
/** This port is captured to one admitted section and page instance. */
export type SettingsSectionPort = {
  save(
    revisionToken: string,
    document: Readonly<Record<string, unknown>>,
  ): Promise<SettingsWriteResult>;
  refresh(): Promise<void>;
  restoreDraft(): unknown;
  retainDraft(value: unknown, dirty: boolean): void;
};
export type SettingsSectionContribution<TComponent = unknown> = SettingsSectionDefinition & {
  readonly component: TComponent;
  readonly read: (snapshot: unknown) => unknown;
};

/** The owner decodes its value type; this reader checks the common settings envelope. */
export function readSettingsSnapshot<T>(
  value: unknown,
  read: (value: unknown) => T,
): SettingsSnapshot<T> {
  if (
    !record(value) ||
    typeof value.token !== "string" ||
    !/^[a-f0-9]{64}$/.test(value.token) ||
    typeof value.version !== "number" ||
    !Number.isSafeInteger(value.version) ||
    value.version < 0 ||
    typeof value.allow_override !== "boolean"
  )
    throw new Error("Invalid settings snapshot.");
  const source = value.source;
  if (
    source !== "organization" &&
    source !== "inherited" &&
    source !== "overridden" &&
    source !== "enforced"
  )
    throw new Error("Invalid settings source.");
  const saved = value.saved === null ? null : read(value.saved);
  if (
    (source === "overridden" && (saved === null || !value.allow_override)) ||
    (source === "inherited" && (saved !== null || !value.allow_override)) ||
    (source === "enforced" && value.allow_override) ||
    (source === "organization" && saved === null)
  )
    throw new Error("Inconsistent settings source.");
  const effective = read(value.effective),
    organizationDefault = read(value.organization_default);
  const expected = source === "overridden" ? saved : organizationDefault;
  if (
    JSON.stringify(effective) !== JSON.stringify(expected) ||
    (source === "organization" && JSON.stringify(saved) !== JSON.stringify(organizationDefault))
  )
    throw new Error("Inconsistent effective settings.");
  return {
    token: value.token,
    version: value.version,
    saved,
    effective,
    organizationDefault,
    allowOverride: value.allow_override,
    source,
  };
}

/** Decode discovery metadata only. Phoenix admits the owner, renderer, reads and actions. */
export function readSettingsSectionDefinition(value: unknown): SettingsSectionDefinition {
  if (!record(value) || value.slot !== SETTINGS_SECTION_SLOT || value.version !== 1)
    throw new Error("Unsupported settings section contract.");
  if (!identifier(value.id) || !text(value.title, 80) || !text(value.description, 400))
    throw new Error("Invalid settings section identity or description.");
  const scopes = value.scopes;
  if (!Array.isArray(scopes) || scopes.length < 1 || scopes.length > 2)
    throw new Error("Settings sections require organization or mission scope.");
  const acceptedScopes: SettingsScope[] = [];
  for (const input of scopes) {
    const scope = readScope(input);
    if (acceptedScopes.includes(scope)) throw new Error("Invalid or duplicate settings scope.");
    acceptedScopes.push(scope);
  }
  const owner = readOwner(value.owner);
  return Object.freeze({
    id: value.id,
    slot: SETTINGS_SECTION_SLOT,
    version: 1,
    scopes: Object.freeze(acceptedScopes),
    title: value.title,
    description: value.description,
    owner,
  });
}

function readScope(value: unknown): SettingsScope {
  if (value === "organization" || value === "mission") return value;
  throw new Error("Invalid settings scope.");
}

function readOwner(value: unknown): SettingsSectionOwner {
  if (!record(value) || !text(value.label, 80)) throw new Error("Invalid settings owner.");
  if (value.kind === "host") return Object.freeze({ kind: "host", label: value.label });
  if (value.kind === "application" && identifier(value.applicationKey))
    return Object.freeze({
      kind: "application",
      applicationKey: value.applicationKey,
      label: value.label,
    });
  throw new Error("Invalid settings owner.");
}
function record(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
function text(value: unknown, max: number): value is string {
  return typeof value === "string" && value.trim().length > 0 && value.length <= max;
}
function identifier(value: unknown): value is string {
  return text(value, 128) && /^[a-z][a-z0-9._-]*$/.test(value);
}
