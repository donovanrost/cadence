export interface FrontendSession {
  schema: "cadence.frontend-session.v1";
  actor: {
    displayName: string;
    email: string;
  };
  authority: {
    role: "platform_admin";
    adminModeExpiresAt: string;
  };
  environment: {
    mode: "development" | "production";
    name: string;
  };
}

export interface SignInCredentials {
  email: string;
  password: string;
}

const sessionPath = "/api/cadence/session";

export async function currentSession(
  fetcher: typeof globalThis.fetch = globalThis.fetch,
): Promise<FrontendSession | undefined> {
  const response = await fetcher(sessionPath, {
    cache: "no-store",
    credentials: "same-origin",
  });
  if (response.status === 204) return undefined;
  if (!response.ok) throw new Error(`The session boundary returned HTTP ${response.status}.`);
  return parseSession(await response.json());
}

export async function signIn(
  credentials: SignInCredentials,
  fetcher: typeof globalThis.fetch = globalThis.fetch,
): Promise<FrontendSession> {
  const response = await fetcher(sessionPath, {
    method: "POST",
    credentials: "same-origin",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(credentials),
  });

  if (!response.ok) throw new Error(await problemMessage(response));
  return parseSession(await response.json());
}

export async function signOut(fetcher: typeof globalThis.fetch = globalThis.fetch): Promise<void> {
  const response = await fetcher(sessionPath, {
    method: "DELETE",
    credentials: "same-origin",
  });
  if (!response.ok) throw new Error(`Sign out returned HTTP ${response.status}.`);
}

function parseSession(value: unknown): FrontendSession {
  if (!isRecord(value) || value.schema !== "cadence.frontend-session.v1") {
    throw new Error("The session boundary returned an incompatible payload.");
  }
  return value as unknown as FrontendSession;
}

async function problemMessage(response: Response): Promise<string> {
  try {
    const problem: unknown = await response.json();
    if (isRecord(problem) && typeof problem.message === "string") return problem.message;
  } catch {
    // Preserve the stable fallback when a proxy returns a non-JSON error page.
  }
  return `Sign in returned HTTP ${response.status}.`;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
