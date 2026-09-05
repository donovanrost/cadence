import { spawn } from "node:child_process";
import { resolve } from "node:path";
import { discoverFirstPartyRemotes } from "./first-party-remote-workspace.mjs";

const frontendRoot = resolve(import.meta.dirname, "..");

export async function buildFirstPartyPublication() {
  const { host, remotes } = await discoverFirstPartyRemotes(frontendRoot);
  const packages = [host, ...remotes];

  for (const { packageName } of packages) {
    await runPnpm(["--filter", packageName, "run", "build:phoenix"]);
  }

  return packages.map(({ packageName, bundle, remoteName }) => ({
    packageName,
    bundle: bundle ?? "host",
    remoteName: remoteName ?? "cadence_host",
  }));
}

function runPnpm(argumentsList) {
  const command = process.platform === "win32" ? "pnpm.cmd" : "pnpm";
  return new Promise((resolveResult, reject) => {
    const child = spawn(command, argumentsList, {
      cwd: frontendRoot,
      env: process.env,
      stdio: "inherit",
    });
    child.once("error", reject);
    child.once("close", (code, signal) => {
      if (code === 0) resolveResult();
      else
        reject(new Error(`${command} ${argumentsList.join(" ")} exited with ${code ?? signal}.`));
    });
  });
}

const isMain = process.argv[1] && resolve(process.argv[1]) === resolve(import.meta.url);
if (isMain) {
  buildFirstPartyPublication().catch((error) => {
    console.error(error instanceof Error ? error.message : error);
    process.exitCode = 1;
  });
}
