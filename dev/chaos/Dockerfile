ARG ELIXIR_IMAGE=elixir:1.20.4-otp-29-slim
FROM node:24.16.0-bookworm-slim AS node
FROM ${ELIXIR_IMAGE} AS source
RUN apt-get update && apt-get install -y --no-install-recommends build-essential ca-certificates git curl && rm -rf /var/lib/apt/lists/*
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm && ln -s /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx && npm install -g corepack@0.34.6
ENV MIX_ENV=prod
WORKDIR /workspace
RUN mix local.hex --force && mix local.rebar --force

FROM source AS server-build
COPY apps/cadence /workspace/apps/cadence
COPY apps/cadence_web /workspace/apps/cadence_web
COPY packages /workspace/packages
COPY frontend /workspace/frontend
WORKDIR /workspace/apps/cadence_web
RUN mix deps.get --only prod && ln -s /workspace/apps/cadence_web/deps /workspace/deps && mix compile
RUN corepack pnpm@11.22.0 --dir ../../frontend install --frozen-lockfile
RUN corepack pnpm@11.22.0 --dir ../../frontend --filter @cadence/console run build
RUN mix release --path /release

FROM source AS simulator-build
COPY apps/cadence_simulator /workspace/apps/cadence_simulator
COPY packages /workspace/packages
WORKDIR /workspace/apps/cadence_simulator
RUN mix deps.get --only prod && mix release --path /simulator-release

FROM ${ELIXIR_IMAGE} AS server
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates libstdc++6 openssl && rm -rf /var/lib/apt/lists/* && useradd --uid 10001 --create-home cadence
WORKDIR /app
COPY --from=server-build --chown=cadence:cadence /release ./
COPY --chown=cadence:cadence dev/reflect_orbital /lab/reflect_orbital
COPY --chown=cadence:cadence dev/chaos/scripts /lab/scripts
COPY --chown=cadence:cadence dev/catalogs/demo_spacecraft.yaml /lab/demo_spacecraft.yaml
RUN for runtime in /app/releases/*/runtime.exs; do test -f "$runtime" && cat /lab/scripts/runtime.exs >> "$runtime"; done
ENV EARENDIL_DATABASE_PATH=/lab/demo_spacecraft.yaml
USER cadence
EXPOSE 4001
CMD ["bin/cadence_web", "start"]

FROM ${ELIXIR_IMAGE} AS simulator
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates libstdc++6 openssl && rm -rf /var/lib/apt/lists/* && useradd --uid 10001 --create-home cadence
WORKDIR /app
COPY --from=simulator-build --chown=cadence:cadence /simulator-release ./
COPY --chown=cadence:cadence dev/chaos/scripts /lab/scripts
COPY --chown=cadence:cadence dev/catalogs/demo_spacecraft.yaml /lab/demo_spacecraft.yaml
USER cadence
CMD ["bin/cadence_simulator", "eval", "Code.eval_file(\"/lab/scripts/simulator.exs\")"]
