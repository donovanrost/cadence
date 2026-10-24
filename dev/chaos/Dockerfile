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

FROM source AS publication-build
COPY apps/cadence /workspace/apps/cadence
COPY apps/cadence_web /workspace/apps/cadence_web
COPY packages /workspace/packages
COPY frontend /workspace/frontend
WORKDIR /workspace/apps/cadence_web
RUN mix deps.get --only prod && ln -s /workspace/apps/cadence_web/deps /workspace/deps && mix compile
RUN npm ci --no-audit --no-fund --foreground-scripts && corepack pnpm@11.22.0 --dir ../../frontend install --frozen-lockfile
# Match config/config.exs. Fetch with curl because the Tailwind wrapper's
# downloader rejects GitHub redirect responses with headers larger than 10 KiB.
RUN case "$(uname -m)" in aarch64) target=arm64 ;; x86_64) target=x64 ;; *) exit 1 ;; esac && \
    mkdir -p _build && \
    curl --fail --location --retry 3 "https://github.com/tailwindlabs/tailwindcss/releases/download/v4.1.12/tailwindcss-linux-${target}" \
      --output "_build/tailwind-linux-${target}-4.1.12" && \
    chmod +x "_build/tailwind-linux-${target}-4.1.12"
# Invoke Vite directly: phoenix_vite.npm loads runtime.exs, which correctly
# requires deployment secrets that must never be supplied to an image build.
RUN mix tailwind cadence_web --minify && npm run build && node ../../frontend/tools/build-first-party-publication.mjs

FROM publication-build AS server-build
RUN node ../../frontend/tools/production-publication-output-check.mjs && mix phx.digest && mix release --path /release

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
COPY --chown=cadence:cadence legacy/cadence_legacy/priv/databases/demo_spacecraft.yaml /lab/demo_spacecraft.yaml
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
COPY --chown=cadence:cadence legacy/cadence_legacy/priv/databases/demo_spacecraft.yaml /lab/demo_spacecraft.yaml
USER cadence
CMD ["bin/cadence_simulator", "eval", "Code.eval_file(\"/lab/scripts/simulator.exs\")"]
