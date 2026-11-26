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

        case AlarmList.load(
               scope.organization_id,
               conn.assigns.current_mission.mission_id,
               filters
             ) do
          {:ok, list} ->
            json(conn, %{data: AlarmJSON.list(list), meta: %{next_cursor: list.next_cursor}})

          {:error, :invalid_cursor} ->
            Problem.respond(conn, :invalid_params, %{cursor: "is not a valid cursor"})
        end

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

    {plane, errors} = integer_param(params, "plane", 0..9_999, errors)
    {limit, errors} = integer_param(params, "limit", 1..200, errors)

    if errors == %{} do
      {:ok,
       %{
         state: state,
         severity: severity,
         spacecraft_id: blank_to_nil(params["spacecraft_id"]),
         query: blank_to_nil(params["q"]),
         point_id: blank_to_nil(params["point_id"]),
         exclude_spacecraft_id: blank_to_nil(params["exclude_spacecraft_id"]),
         plane: plane,
         limit: limit,
         cursor: blank_to_nil(params["cursor"])
       }}
    else
      {:error, errors}
    end
  end

  # An optional integer in `range`; a bad one is an error naming the range.
  defp integer_param(params, key, range, errors) do
    case params[key] do
      blank when blank in [nil, ""] ->
        {nil, errors}

      value when is_binary(value) ->
        case parse_in(value, range) do
          {:ok, n} -> {n, errors}
          :error -> {nil, out_of_range(errors, key, range)}
        end

      _other ->
        {nil, Map.put(errors, key, "must be an integer")}
    end
  end

  defp parse_in(value, range) do
    with {n, ""} <- Integer.parse(value),
         true <- n in range do
      {:ok, n}
    else
      _bad -> :error
    end
  end

  defp out_of_range(errors, key, range),
    do: Map.put(errors, key, "must be an integer from #{range.first} to #{range.last}")

  defp put_error(errors, true, key, message), do: Map.put(errors, key, message)
  defp put_error(errors, false, _key, _message), do: errors

  defp blank_to_nil(value) when is_binary(value) and value != "", do: value
  defp blank_to_nil(_value), do: nil
end
