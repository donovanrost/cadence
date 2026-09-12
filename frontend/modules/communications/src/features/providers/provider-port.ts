export type ProviderAction =
  | "create_provider"
  | "validate_provider"
  | "sync_provider"
  | "archive_provider";
export type ProviderPort = {
  execute(action: ProviderAction, input: Record<string, unknown>): Promise<unknown>;
  query(): Promise<unknown>;
  navigate(href: string): void;
};
