import type { InjectionKey, Ref } from "vue";

export interface CatalogUploadSession {
  path: string;
  token: string;
  error: string | null;
  attempt: number;
}
export interface CatalogUploadTransport {
  busy: Ref<boolean>;
  error: Ref<string | null>;
  validate(values: Record<string, string>): void;
  select(files: File[], values: Record<string, string>): void;
  submit(values: Record<string, string>): void;
  cancel(ref: string): void;
}
export type CatalogUploadCancel = (params: {
  catalog_upload: { path: string; token: string };
  ref: string;
}) => void;
export const catalogUploadKey: InjectionKey<CatalogUploadTransport> = Symbol("catalog-upload");

export function isCatalogUploadSession(value: unknown): value is CatalogUploadSession {
  if (typeof value !== "object" || value === null) return false;
  const session = value as Record<string, unknown>;
  return (
    typeof session.path === "string" &&
    session.path.startsWith("/missions/") &&
    typeof session.token === "string" &&
    session.token.length > 0 &&
    (session.error === null || typeof session.error === "string") &&
    Number.isSafeInteger(session.attempt) &&
    Number(session.attempt) >= 0
  );
}
