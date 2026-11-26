defmodule CadenceWeb.Console.AlarmController do
  @moduledoc "`GET /api/v1/missions/:mission_id/alarms`. Contract: docs/apogee/api/ops.md."

  use CadenceWeb, :controller

  alias Cadence.Reads.AlarmList
  alias CadenceWeb.Console.{AlarmJSON, Problem}

  @states ~w(active nominal all)
  @severities ~w(critical caution)

  def index(conn, params) do
    case filters(params) do
      {:ok, filters} ->
        scope = conn.assigns.current_scope

        list =
          AlarmList.load(scope.organization_id, conn.assigns.current_mission.mission_id, filters)

        json(conn, %{data: AlarmJSON.list(list)})

      {:error, details} ->
        Problem.respond(conn, :invalid_params, details)
    end
  end

  defp filters(params) do
    state = Map.get(params, "state", "active")
    severity = Map.get(params, "severity")

    errors =
      %{}
      |> put_error(state not in @states, :state, "must be one of #{Enum.join(@states, ", ")}")
      |> put_error(
        not is_nil(severity) and severity not in @severities,
        :severity,
        "must be one of #{Enum.join(@severities, ", ")}"
      )

    if errors == %{} do
      {:ok,
       %{
         state: state,
         severity: severity,
         spacecraft_id: blank_to_nil(params["spacecraft_id"]),
         query: blank_to_nil(params["q"])
       }}
    else
      {:error, errors}
    end
  end

  defp put_error(errors, true, key, message), do: Map.put(errors, key, message)
  defp put_error(errors, false, _key, _message), do: errors

  defp blank_to_nil(value) when is_binary(value) and value != "", do: value
  defp blank_to_nil(_value), do: nil
end
