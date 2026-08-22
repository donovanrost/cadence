ARG ELIXIR_IMAGE=elixir:1.20.2-otp-28-slim

FROM ${ELIXIR_IMAGE} AS build

RUN apt-get update \
    && apt-get install --yes --no-install-recommends build-essential ca-certificates git \
    && rm -rf /var/lib/apt/lists/*

ENV MIX_ENV=prod
WORKDIR /workspace

RUN mix local.hex --force && mix local.rebar --force

COPY apps/cadence_simulator/mix.exs ./apps/cadence_simulator/mix.exs
COPY apps/cadence_simulator/mix.lock ./apps/cadence_simulator/mix.lock
COPY apps/cadence_simulator/config ./apps/cadence_simulator/config
COPY packages/cadence_catalog/mix.exs ./packages/cadence_catalog/mix.exs
COPY packages/cadence_catalog/mix.lock ./packages/cadence_catalog/mix.lock
COPY packages/ccsds/mix.exs ./packages/ccsds/mix.exs
COPY packages/ccsds/mix.lock ./packages/ccsds/mix.lock

WORKDIR /workspace/apps/cadence_simulator
RUN mix deps.get --only prod

WORKDIR /workspace
COPY apps/cadence_simulator/lib ./apps/cadence_simulator/lib
COPY packages/cadence_catalog/lib ./packages/cadence_catalog/lib
COPY packages/ccsds/lib ./packages/ccsds/lib

WORKDIR /workspace/apps/cadence_simulator
RUN mix escript.build

FROM ${ELIXIR_IMAGE} AS cadence-full-flow

RUN apt-get update \
    && apt-get install --yes --no-install-recommends build-essential ca-certificates git \
    && rm -rf /var/lib/apt/lists/*

ENV MIX_ENV=dev
WORKDIR /workspace

RUN mix local.hex --force && mix local.rebar --force

COPY . .

RUN mix deps.get && mix compile

CMD ["mix", "run", "--no-start", "dev/ingress-benchmark/full_flow_runner.exs"]

FROM ${ELIXIR_IMAGE} AS runtime

RUN apt-get update \
    && apt-get install --yes --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /workspace/apps/cadence_simulator/cadence_simulator /usr/local/bin/cadence_simulator

ENTRYPOINT ["cadence_simulator"]
CMD ["ingress_preflight", "--manifest", "/benchmark/config/run-manifest.yaml"]
