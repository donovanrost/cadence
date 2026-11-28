defmodule Cadence.Dashboards.Sources.OperationalObservables.ConstellationHealth do
  @moduledoc """
  Resolves the constellation-health operational observable product.

  The family owns provider selection, limit-state rollup, and frame
  presentation. The source adapter supplies tenant context and source identity.
  """

  alias Cadence.Dashboards.{Field, Frame, PlannedSourceRequest}
  alias Cadence.Limits.Event
  alias Cadence.Reads.{MonitoredParameters, OperationalState}
  alias Cadence.SemanticObservations.FleetAlarms
  alias Cadence.Spacecraft

  @state_severity %{red: 3, yellow: 2, blue: 1, green: 0}

  @type latest_states_fun :: (binary() | nil, binary(), keyword() -> [Event.t()])
  @type spacecraft_fun :: (binary() | nil, binary(), keyword() -> [Spacecraft.t()])

  @spec resolve(
          PlannedSourceRequest.t(),
          binary(),
          binary(),
          map(),
          keyword(),
          keyword()
        ) :: Frame.t()
  def resolve(
        %PlannedSourceRequest{} = request,
        organization_id,
        mission_id,
        source_context,
        adapter_opts,
        opts
      ) do
    latest_states_fun = Keyword.get(opts, :latest_states_fun, &default_latest_states/3)
    spacecraft_fun = Keyword.get(opts, :spacecraft_fun, &default_spacecraft/3)
    spacecraft = spacecraft_fun.(organization_id, mission_id, adapter_opts)
    states = latest_states_fun.(organization_id, mission_id, adapter_opts)

    frame(
      request,
      spacecraft,
      with_nominal(opts, organization_id, mission_id, spacecraft, states),
      source_context
    )
  end

  @spec frame(PlannedSourceRequest.t(), [Spacecraft.t()], [Event.t()], map()) :: Frame.t()
  def frame(%PlannedSourceRequest{} = request, spacecraft, point_states, source_context) do
    rollup = rollup(spacecraft, point_states)

    %Frame{
      frame_id: "#{request.request_id}:constellation_health",
      source: :operational_observables,
      shape: :matrix,
      time_axis: nil,
      scope: request.scope_context,
      fields: [
        %Field{
          name: "spacecraft_id",
          kind: :string,
          values: Enum.map(rollup.spacecraft, & &1.spacecraft_id)
        },
        %Field{
          name: "worst_state",
          kind: :enum,
          values: Enum.map(rollup.spacecraft, & &1.worst_state)
        }
      ],
      meta:
        Map.merge(source_context, %{
          source_request_id: request.request_id,
          logical_source: :operational_observables,
          sampling: :constellation_health,
          counts: rollup.counts,
          returned_points: length(rollup.spacecraft),
          warning_codes: []
        })
    }
  end

  defp rollup(spacecraft, point_states) do
    worst_by_spacecraft =
      point_states
      |> Enum.reject(&is_nil(&1.spacecraft_id))
      |> Enum.group_by(& &1.spacecraft_id, & &1.normalized_state)
      |> Map.new(fn {spacecraft_id, states} -> {spacecraft_id, worst_state(states)} end)

    spacecraft_entries =
      Enum.map(spacecraft, fn spacecraft ->
        %{
          spacecraft_id: spacecraft.spacecraft_id,
          worst_state: Map.get(worst_by_spacecraft, spacecraft.spacecraft_id)
        }
      end)

    counts =
      spacecraft_entries
      |> Enum.group_by(&(&1.worst_state || :no_data))
      |> Map.new(fn {state, entries} -> {state, length(entries)} end)

    %{counts: counts, spacecraft: spacecraft_entries}
  end

  defp worst_state(states) do
    Enum.max_by(states, &Map.get(@state_severity, &1, -1))
  end

  # The runtime's alarms, one state per alarming spacecraft (its worst), from the fleet summary the
  # alarm writers keep (#451 T3e): one statement however many spacecraft there are, never every
  # state of the mission.
  defp default_latest_states(organization_id, mission_id, _opts) do
    organization_id
    |> FleetAlarms.load(mission_id)
    |> Enum.map(fn {spacecraft_id, alarm} ->
      %Event{spacecraft_id: spacecraft_id, normalized_state: normalized(alarm.limit_state)}
    end)
  end

  defp normalized(:critical), do: :red
  defp normalized(:caution), do: :yellow

  # A mission whose plan monitors something has every spacecraft with no alarm nominal; one that
  # monitors nothing has them `no_data`. Only for the default state source: a caller that supplies
  # its own states says what it means.
  defp with_nominal(opts, organization_id, mission_id, spacecraft, states) do
    if Keyword.has_key?(opts, :latest_states_fun) or
         not MonitoredParameters.configured?(organization_id, mission_id) do
      states
    else
      alarming = MapSet.new(states, & &1.spacecraft_id)

      states ++
        for %{spacecraft_id: id} <- spacecraft,
            not MapSet.member?(alarming, id),
            do: %Event{spacecraft_id: id, normalized_state: :green}
    end
  end

  defp default_spacecraft(organization_id, mission_id, _opts) do
    OperationalState.list_spacecraft(organization_id, mission_id)
  end
end
