defmodule Cadence.Runtime.PartitionOwner.ScidRoutesCache do
  @moduledoc """
  A partition's `Cadence.Protocol.ScidRoutes` (#1078 P5 slice E1b): built when the partition
  starts and at each activation, and for a relay endpoint refreshed on a clock, so a reviewed
  change to its relay set takes effect without a restart. A non-relay endpoint's own craft SCID
  changes with a configuration change that is itself an activation, so it is never polled.

  The data plane reads no management table: the builder is configured,
  `config :cadence, :scid_routes, module: Cadence.Control.ScidRoutes, refresh_ms: 60_000`, and
  with no module the routes check nothing.
  """

  alias Cadence.Protocol.ScidRoutes
  alias Cadence.Runtime.PartitionKey

  @default_refresh_ms 60_000

  @type t :: %{routes: ScidRoutes.t(), built_at: integer()}

  @doc "The routes of the partition's source endpoint, built now."
  @spec build(map(), PartitionKey.t()) :: t()
  def build(activation, %PartitionKey{affinity: :source_endpoint, value: endpoint}) do
    %{routes: fetch(activation, endpoint), built_at: now_ms()}
  end

  def build(_activation, _partition_key), do: %{routes: ScidRoutes.none(), built_at: now_ms()}

  @doc "The routes to decode with, and the cache (refreshed when a relay's are stale)."
  @spec current(t(), map(), PartitionKey.t()) :: {ScidRoutes.t(), t()}
  def current(%{routes: routes, built_at: built_at} = cache, activation, partition_key) do
    if ScidRoutes.relay?(routes) and now_ms() - built_at >= refresh_ms() do
      refreshed = build(activation, partition_key)
      {refreshed.routes, refreshed}
    else
      {routes, cache}
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
  defp settings, do: Application.get_env(:cadence, :scid_routes, [])
  defp now_ms, do: System.monotonic_time(:millisecond)
end
