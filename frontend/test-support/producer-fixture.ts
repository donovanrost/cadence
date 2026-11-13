import { appendFileSync } from "node:fs";
import { relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const frontendRoot = resolve(import.meta.dirname, "..");

/** Optional in the unit suite; mandatory and accounted for in the producer contract gate. */
export function producerFixture(
  name: string,
  testModule: string,
  environment: NodeJS.ProcessEnv = process.env,
) {
  const value = environment[name];
  const available = typeof value === "string" && value.trim().length > 0;
  const required = environment.CADENCE_REQUIRE_PRODUCER_FIXTURES === "1";
  if (required && !available) throw Error(`Missing required producer fixture: ${name}`);

  return {
    available,
    read(): string {
      if (!available || value === undefined) throw Error(`Missing producer fixture: ${name}`);
      // The gate requires a ledger. Outside it, a ledger is still written when one is named, so
      // CI's test shards can prove coverage without making every fixture mandatory there.
      const ledger = environment.CADENCE_PRODUCER_FIXTURE_LEDGER;
      if (required || ledger) {
        if (!ledger) throw Error("Missing producer fixture execution ledger");
        const consumer = relative(frontendRoot, fileURLToPath(testModule));
        if (consumer.startsWith(`..${sep}`) || !consumer.endsWith(".test.ts")) {
          throw Error("Producer consumer must be a frontend test module");
        }
        appendFileSync(ledger, `${consumer.split(sep).join("/")}\n`);
      }
      return value;
    },
  };
}
