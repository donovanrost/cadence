defmodule Cadence.Reads.MonitoredParameters do
  @moduledoc """
  Which parameters the mission's active monitoring plan evaluates, per spacecraft (#451 T3a).

  The compiled plan is the inventory: a parameter is monitored on a craft when the plan has an
  enabled entry that resolves for it (`MonitoringPlan.resolve/2`: the craft's own entry over the
  mission's, another craft's dropped). This replaces asking `governed_limit_definitions` what
  limits exist, for PointConditions' "not evaluated" rows and for "is anything configured".

  **Cost.** A revision's plans never change, so the summary of a revision's monitoring plan (the
  mission's monitored parameters, plus the few parameters a craft's own entry adds or turns off)
  is built once per node and kept in an ETS table owned by this process, newest
  #{16} revisions only. A read is the active activation's lookup plus one ETS read, and never
  decodes the plan again, however many spacecraft or reads. Without the process (a unit test that
  does not start the application) every read builds it.
  """

  use GenServer

  alias Cadence.MissionModels
  alias Cadence.Reads.MissionModels.ActiveBasis
  alias Cadence.SemanticRuntime.{MonitoringPlan, PlanDecoder}

  @table __MODULE__
  @keep 16

  @typedoc "`mission`: monitored on every craft; `craft`: per spacecraft, what its own entries add (`on`) or turn off (`off`)."
  @type summary :: %{
          mission: MapSet.t(binary()),
          craft: %{optional(binary()) => %{on: MapSet.t(binary()), off: MapSet.t(binary())}}
        }

  @doc """
  The parameters monitored on `spacecraft_id`, or `:none` when the mission has no active monitoring
  plan. `opts[:revision_id]` reads another revision's plan than the active one.
  """
  @spec for_spacecraft(binary(), binary(), binary(), keyword()) ::
          {:ok, MapSet.t(binary())} | :none
  def for_spacecraft(organization_id, mission_id, spacecraft_id, opts \\ []) do
    with {:ok, summary} <- summary(organization_id, mission_id, opts) do
      {:ok, monitored_on(summary, spacecraft_id)}
    end
  end

  @doc "Whether the active plan evaluates any parameter on any craft."
  @spec configured?(binary(), binary(), keyword()) :: boolean()
  def configured?(organization_id, mission_id, opts \\ []) do
    case summary(organization_id, mission_id, opts) do
      {:ok, %{mission: mission, craft: craft}} ->
        MapSet.size(mission) > 0 or
          Enum.any?(craft, fn {_id, %{on: on}} -> MapSet.size(on) > 0 end)

      :none ->
        false
    end
  end

  @doc "The summary of a decoded plan's entries (pure; the cache stores this)."
  @spec summarize([MonitoringPlan.t()]) :: summary()
  def summarize(entries) do
    by_parameter = Enum.group_by(entries, & &1.parameter_id)
    crafts = entries |> Enum.flat_map(&craft_of/1) |> Enum.uniq()

    mission =
      for {parameter, group} <- by_parameter,
          enabled?(group, nil),
          into: MapSet.new(),
          do: parameter

    craft =
      Map.new(crafts, fn craft ->
        {craft, craft_delta(by_parameter, mission, craft)}
      end)

    %{mission: mission, craft: craft}
  end

  defp craft_of(%MonitoringPlan{scope: :spacecraft, spacecraft_id: id}) when is_binary(id),
    do: [id]

  defp craft_of(%MonitoringPlan{}), do: []

  # Only the parameters that carry an entry of the craft's own can differ from the mission's.
  defp craft_delta(by_parameter, mission, craft) do
    own =
      for {parameter, group} <- by_parameter,
          Enum.any?(group, &(&1.scope == :spacecraft and &1.spacecraft_id == craft)),
          do: {parameter, enabled?(group, craft)}

    %{
      on:
        for(
          {parameter, true} <- own,
          not MapSet.member?(mission, parameter),
          into: MapSet.new(),
          do: parameter
        ),
      off:
        for(
          {parameter, false} <- own,
          MapSet.member?(mission, parameter),
          into: MapSet.new(),
          do: parameter
        )
    }
  end

  defp enabled?(group, craft),
    do: group |> MonitoringPlan.resolve(craft) |> Enum.any?(&(not &1.disabled))

  defp monitored_on(%{mission: mission, craft: craft}, spacecraft_id) do
    case Map.get(craft, spacecraft_id) do
      nil -> mission
      %{on: on, off: off} -> mission |> MapSet.difference(off) |> MapSet.union(on)
    end
  end

  # `:revision_id` names the revision for a caller that already holds it; otherwise the mission's
  # active one.
  defp summary(organization_id, mission_id, opts) do
    revision_id =
      Keyword.get_lazy(opts, :revision_id, fn ->
        ActiveBasis.active_revision_id(organization_id, mission_id)
      end)

    case revision_id do
      nil ->
        :none

      revision_id ->
        {:ok,
         cached({mission_id, revision_id}, fn ->
           build(organization_id, mission_id, revision_id)
         end)}
    end
  end

  defp build(organization_id, mission_id, revision_id) do
    case MissionModels.fetch_plan(organization_id, mission_id, revision_id, :monitoring) do
      {:ok, plan} ->
        %{monitoring: plan} |> PlanDecoder.decode() |> Map.fetch!(:monitoring) |> summarize()

      {:error, _not_found} ->
        %{mission: MapSet.new(), craft: %{}}
    end
  end

  defp cached(key, build) do
    case :ets.whereis(@table) do
      :undefined ->
        build.()

      _table ->
        case :ets.lookup(@table, key) do
          [{^key, _at, summary}] ->
            summary

          [] ->
            summary = build.()
            GenServer.cast(__MODULE__, {:put, key, summary})
            summary
        end
    end
  end

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :protected, :set, read_concurrency: true])
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:put, key, summary}, state) do
    :ets.insert(@table, {key, System.monotonic_time(), summary})

    @table
    |> :ets.tab2list()
    |> Enum.sort_by(&elem(&1, 1), :desc)
    |> Enum.drop(@keep)
    |> Enum.each(&:ets.delete(@table, elem(&1, 0)))

    {:noreply, state}
  end
end
