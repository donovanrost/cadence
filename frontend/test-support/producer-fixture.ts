/** A Phoenix-produced fixture passed in by the producer test; absent in the plain unit suite. */
export function producerFixture(name: string, environment: NodeJS.ProcessEnv = process.env) {
  const value = environment[name];
  const available = typeof value === "string" && value.trim().length > 0;

  return {
    available,
    read(): string {
      if (!available || value === undefined) throw Error(`Missing producer fixture: ${name}`);
      return value;
    },
  };
}
