defmodule Cadence.Runtime.PartitionOwner.ScidRoutesCache do
  @moduledoc """
  A partition's `Cadence.Protocol.ScidRoutes` (#1078 P5 slice E1b): built when the partition
  starts and at each activation, and refreshed after that, because a craft's SCID is edited through
  the spacecraft API with no activation, and a relay's set through a reviewed change:

    * a relay's routes are re-read every `refresh_ms` (60 s);
    * a non-relay endpoint's are re-read every `idle_refresh_ms` (5 min), and **sooner when a batch
      was refused**: a refusal is the sign a stale SCID shows, so the next batch (after
      `retry_ms`, 5 s, so a genuinely foreign frame stream doesn't read on every batch) reads the
      fixed SCID. No steady-state cost for the fleet: 500 endpoints are about 3 reads a second
      at the idle clock, and none while nothing is refused.

  The data plane reads no management table: the builder is configured,
  `config :cadence, :scid_routes, module: Cadence.Control.ScidRoutes, refresh_ms: 60_000`, and
  with no module the routes check nothing.
  """

  alias Cadence.Protocol.ScidRoutes
  alias Cadence.Runtime.PartitionKey

  @default_refresh_ms 60_000
  @default_idle_refresh_ms 300_000
  @default_retry_ms 5_000

  @type t :: %{routes: ScidRoutes.t(), built_at: integer(), refused?: boolean()}

  @doc "The routes of the partition's source endpoint, built now."
  @spec build(map(), PartitionKey.t()) :: t()
  def build(activation, %PartitionKey{affinity: :source_endpoint, value: endpoint}) do
    %{routes: fetch(activation, endpoint), built_at: now_ms(), refused?: false}
  end

  def build(_activation, _partition_key),
    do: %{routes: ScidRoutes.none(), built_at: now_ms(), refused?: false}

  @doc "Notes that a decode refused frames, so the routes are re-read soon (after `retry_ms`)."
  @spec note_refusals(t(), map()) :: t()
  def note_refusals(cache, %{scid_check: %{refused: refused}}) when map_size(refused) > 0,
    do: %{cache | refused?: true}

  def note_refusals(cache, _decode_result), do: cache

  @doc "The routes to decode with, and the cache (refreshed when a relay's are stale)."
  @spec current(t(), map(), PartitionKey.t()) :: {ScidRoutes.t(), t()}
  def current(%{routes: routes} = cache, activation, partition_key) do
    if stale?(cache) do
      refreshed = build(activation, partition_key)
      {refreshed.routes, refreshed}
    else
      {routes, cache}
    end
  end

  defp stale?(%{routes: routes, built_at: built_at, refused?: refused?}) do
    age = now_ms() - built_at

    cond do
      ScidRoutes.relay?(routes) -> age >= refresh_ms()
      refused? -> age >= retry_ms()
      true -> age >= idle_refresh_ms()
    end
  end

  defp fetch(%{organization_id: org, mission_id: mission}, endpoint)
       when is_binary(org) and is_binary(mission) and is_binary(endpoint) do
    case module() do
      nil -> ScidRoutes.none()
      module -> module.build(org, mission, endpoint)
    end
  rescue
    # A read that fails refuses no frame.
    _error -> ScidRoutes.none()
  end

  defp fetch(_activation, _endpoint), do: ScidRoutes.none()

  defp module, do: Keyword.get(settings(), :module)
  defp refresh_ms, do: Keyword.get(settings(), :refresh_ms, @default_refresh_ms)
  defp idle_refresh_ms, do: Keyword.get(settings(), :idle_refresh_ms, @default_idle_refresh_ms)
  defp retry_ms, do: Keyword.get(settings(), :retry_ms, @default_retry_ms)
  defp settings, do: Application.get_env(:cadence, :scid_routes, [])
  defp now_ms, do: System.monotonic_time(:millisecond)
end
