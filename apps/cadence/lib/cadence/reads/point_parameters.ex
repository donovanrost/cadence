defmodule Cadence.Reads.PointParameters do
  @moduledoc """
  Which parameter a point is (and the other way round), for the readers that join the runtime's
  alarm tables (keyed by parameter) with what operators name (points): `%{by_point: %{point_id =>
  parameter_id}, by_parameter: %{parameter_id => point_id}}` over the mission's point catalog
  (`Ops.PointCatalog`).

  The dashboards' limits source asks per observable and per product, tens of times in one resolve,
  so the answer is kept per mission for #{10} seconds in an ETS table owned by this process (a read
  is one lookup, a refresh one catalog read); the catalog only changes with an activation, and a
  mapping at most ten seconds old is what an overlay can use. Newest 64 missions kept. Without the
  process (a unit test that does not start the application) every read builds.
  """

  use GenServer

  alias Cadence.Ops.PointCatalog

  @table __MODULE__
  @ttl_ms 10_000
  @keep 64

  @type mapping :: %{
          by_point: %{optional(binary()) => binary()},
          by_parameter: %{optional(binary()) => binary()}
        }

  @doc "The point/parameter mapping of the mission's catalog."
  @spec mapping(binary(), binary()) :: mapping()
  def mapping(organization_id, mission_id) do
    key = {organization_id, mission_id}
    now = System.monotonic_time(:millisecond)

    case :ets.whereis(@table) do
      :undefined ->
        build(organization_id, mission_id)

      _table ->
        case :ets.lookup(@table, key) do
          [{^key, at, mapping}] when now - at < @ttl_ms ->
            mapping

          _missing_or_stale ->
            mapping = build(organization_id, mission_id)
            GenServer.cast(__MODULE__, {:put, key, now, mapping})
            mapping
        end
    end
  end

  defp build(organization_id, mission_id) do
    points = PointCatalog.list_points(organization_id, mission_id)

    %{
      by_point: for(p <- points, into: %{}, do: {p.point_id, p.parameter_id || p.point_id}),
      by_parameter:
        for(p <- points, is_binary(p.parameter_id), into: %{}, do: {p.parameter_id, p.point_id})
    }
  end

  @doc false
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :protected, :set, read_concurrency: true])
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:put, key, at, mapping}, state) do
    :ets.insert(@table, {key, at, mapping})

    @table
    |> :ets.tab2list()
    |> Enum.sort_by(&elem(&1, 1), :desc)
    |> Enum.drop(@keep)
    |> Enum.each(&:ets.delete(@table, elem(&1, 0)))

    {:noreply, state}
  end
end
