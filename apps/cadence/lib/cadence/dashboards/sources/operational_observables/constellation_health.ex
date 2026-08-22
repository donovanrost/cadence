defmodule Cadence.Dashboards.Sources.OperationalObservables.ConstellationHealth do
  @moduledoc """
  Resolves the constellation-health operational observable product.

  The family owns provider selection, limit-state rollup, and frame
  presentation. The source adapter supplies tenant context and source identity.
  """

  alias Cadence.Dashboards.{Field, Frame, PlannedSourceRequest}
  alias Cadence.Limits.Event
  alias Cadence.Reads.Limits, as: LimitReads
  alias Cadence.Reads.OperationalState
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

    frame(
      request,
      spacecraft_fun.(organization_id, mission_id, adapter_opts),
      latest_states_fun.(organization_id, mission_id, adapter_opts),
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

  defp default_latest_states(organization_id, mission_id, _opts) do
    LimitReads.latest_states_for_mission(organization_id, mission_id, [])
  end

  defp default_spacecraft(organization_id, mission_id, _opts) do
    OperationalState.list_spacecraft(organization_id, mission_id)
  end
end
