// The browser smokes' one sign-in path. Since L5 (ecdddab10) the legacy /sign-in page 302s to the
// console's sign-in screen, so the smokes sign in through the console's JSON API instead
// (docs/apogee/api/session.md §Sign-in and invitation links). The screen itself has its own e2e
// (frontend/apps/console/e2e), so the smokes skip it.

export const CONSOLE_SIGN_IN_PATH = "/console/sign-in";
export const CONSOLE_SIGN_IN_API_PATH = "/api/v1/auth/sign-in";
/** The console bootstrap read; signed out it answers 401 (its sign-in screen asks first). */
export const CONSOLE_SESSION_PATH = "/api/v1/session";

/**
 * Runs IN THE PAGE, on the Phoenix origin: reads the CSRF token the console document carries for
 * this browser session, then posts the credentials. The session cookie lands in the browser's
 * cookie jar, so the next navigation is signed in. It needs the built console
 * (`apps/cadence_web/priv/static/console/index.html`); without it /console/sign-in answers 503.
 * Self-contained, because Playwright and CDP both serialize it into the page.
 * @param {{email: string, password: string, documentPath: string, apiPath: string}} request
 * @returns {Promise<{status: number, redirectTo: string | null, detail: string}>}
 */
export async function consoleSignInInPage({ email, password, documentPath, apiPath }) {
  const page = await fetch(documentPath, { credentials: "same-origin" });
  const html = await page.text();
  if (!page.ok) return { status: page.status, redirectTo: null, detail: html.slice(0, 300) };
  const meta = new DOMParser()
    .parseFromString(html, "text/html")
    .querySelector('meta[name="csrf-token"]');
  const token = meta?.getAttribute("content");
  if (!token)
    return { status: 0, redirectTo: null, detail: "no csrf-token meta on the console document" };
  const response = await fetch(apiPath, {
    method: "POST",
    credentials: "same-origin",
    headers: {
      accept: "application/json",
      "content-type": "application/json",
      "x-csrf-token": token,
    },
    body: JSON.stringify({ email, password }),
  });
  const body = await response.text();
  /** @type {unknown} */
  let parsed = null;
  try {
    parsed = JSON.parse(body);
  } catch {
    parsed = null;
  }
  const data =
    parsed &&
    typeof parsed === "object" &&
    "data" in parsed &&
    parsed.data &&
    typeof parsed.data === "object"
      ? /** @type {Record<string, unknown>} */ (parsed.data)
      : {};
  const redirectTo = typeof data.redirect_to === "string" ? data.redirect_to : null;
  // Never echo the request; the response body holds no secret (an error code or redirect_to).
  return { status: response.status, redirectTo, detail: body.slice(0, 300) };
}

/** @param {{email: string, password: string}} credentials */
export function consoleSignInRequest({ email, password }) {
  return { email, password, documentPath: CONSOLE_SIGN_IN_PATH, apiPath: CONSOLE_SIGN_IN_API_PATH };
}

/**
 * The same sign-in as a CDP `Runtime.evaluate` expression (awaitPromise).
 * @param {{email: string, password: string}} credentials
 */
export function consoleSignInExpression(credentials) {
  return `(${consoleSignInInPage.toString()})(${JSON.stringify(consoleSignInRequest(credentials))})`;
}

/** @param {{status: number, redirectTo: string | null, detail: string}} result */
export function assertConsoleSignedIn(result) {
  if (result.status !== 200 || !result.redirectTo)
    throw new Error(
      `console sign-in failed (HTTP ${String(result.status)}): ${result.detail}` +
        (result.status === 503 ? " (build the console: frontend/apps/console)" : ""),
    );
}

/**
 * Playwright: sign the page's browser context in, then open `path`. The path is required: since
 * §11c the legacy app root redirects to the console, so a default would silently leave the
 * Phoenix host. The in-page fetches need a same-origin document, so the page first opens the JSON
 * health endpoint (signed out, and it boots no app).
 * @param {import("playwright").Page} page
 * @param {{base: string, email: string, password: string, path: string}} options
 */
export async function signInThroughConsole(page, { base, email, password, path }) {
  if (typeof path !== "string" || !path.startsWith("/"))
    throw new Error("signInThroughConsole needs an absolute path to open after signing in");
  await page.goto(base + "/health/live");
  const result = await page.evaluate(
    consoleSignInInPage,
    consoleSignInRequest({ email, password }),
  );
  assertConsoleSignedIn(result);
  await page.goto(base + path);
}
