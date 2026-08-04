defmodule CadenceWeb.OpsDashboardShowLive.RevisionDecisionCommands do
  @moduledoc false

  alias Cadence.Telemetry.Storage, as: TelemetryStorage

  alias Cadence.Control.TelemetryDataManagement, as: DataManagement

  alias CadenceWeb.OpsDashboardShowLive.RevisionDecisionParams

  def apply_decision(params, scope, mission, opts \\ [])
      when is_map(params) and is_list(opts) do
    params = RevisionDecisionParams.new(params)
    attrs = RevisionDecisionParams.attrs(params, scope, mission)

    case {params.observation_identity_id, params.decision} do
      {nil, _decision} ->
        {:error, {:missing_field, :observation_identity_id}}

      {_observation_identity_id, nil} ->
        {:error, {:missing_field, :decision}}

      {observation_identity_id, decision} ->
        with {:ok, state} <-
               DataManagement.apply_observation_identity_decision(
                 observation_identity_id,
                 decision,
                 attrs,
                 opts
               ),
             {:ok, event} <- latest_decision_event(state.observation_identity_id, attrs, opts) do
          {:ok, state, event}
        end
    end
  end

  defp latest_decision_event(observation_identity_id, attrs, opts) do
    query_opts =
      attrs
      |> Map.take([:organization_id, :mission_id, :realm, :data_source_id, :binding_id])
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Keyword.new()
      |> Keyword.merge(Keyword.take(opts, [:dashboard_runtime_invalidation?]))

    observation_identity_id
    |> TelemetryStorage.list_observation_identity_decision_events(query_opts)
    |> List.last()
    |> case do
      nil -> {:error, :telemetry_revision_decision_event_not_found}
      event -> {:ok, event}
    end
  end
end
