defmodule CadenceWeb.Console.PassController do
  @moduledoc """
  `GET /api/console/v1/missions/:mission_id/passes` (ops M7 = scheduling S1).
  Contract: docs/apogee/api/contacts.md.
  """

  use CadenceWeb, :controller

  alias Cadence.ContactPlanning.RepairChain
  alias Cadence.Reads.Passes
  alias CadenceWeb.Console.{PassJSON, Problem, WindowParams}

  @max_span_s 7 * 86_400
  @default_span_s 86_400
  @states ~w(requesting pending confirmed active completed unknown rejected canceling canceled failed)

  def index(conn, params) do
    with {:ok, window} <- WindowParams.parse(with_defaults(params), max_span_s: @max_span_s),
         {:ok, states} <- states(params["states"]) do
      result =
        Passes.load(org_id(conn), mission_id(conn), window.from, window.to, %{
          spacecraft_id: window.spacecraft_id,
          station: blank_to_nil(params["station"]),
          states: states
        })

      json(conn, %{data: PassJSON.passes(with_replacements(conn, result))})
    else
      {:error, {:invalid_params, details}} -> Problem.respond(conn, :invalid_params, details)
    end
  end

  # qa #30: a lost booking that an applied repair replaced says by which plan and booking.
  defp with_replacements(conn, %{passes: passes} = result) do
    replaced =
      RepairChain.replacements_for(
        org_id(conn),
        mission_id(conn),
        for(%{plan: %{id: plan_id}, ended_by: %{}} <- passes, do: plan_id)
      )

    %{result | passes: Enum.map(passes, &Map.put(&1, :replaced_by, Map.get(replaced, &1.id)))}
  end

  # Passes look forward: by default `from` is now and `to` is a day later.
  defp with_defaults(params) do
    now = DateTime.utc_now() |> DateTime.truncate(:millisecond)

    from =
      case DateTime.from_iso8601(params["from"] || "") do
        {:ok, from, _offset} -> from
        _missing -> now
      end

    params
    |> Map.put_new_lazy("from", fn -> DateTime.to_iso8601(now) end)
    |> Map.put_new_lazy("to", fn -> DateTime.to_iso8601(DateTime.add(from, @default_span_s)) end)
  end

  defp states(nil), do: {:ok, nil}
  defp states(""), do: {:ok, nil}

  defp states(value) when is_binary(value) do
    states = value |> String.split(",", trim: true) |> Enum.map(&String.trim/1)

    if Enum.all?(states, &(&1 in @states)),
      do: {:ok, states},
      else:
        {:error,
         {:invalid_params, %{"states" => "must be a comma list of #{Enum.join(@states, ", ")}"}}}
  end

  defp states(_value), do: {:error, {:invalid_params, %{"states" => "must be a comma list"}}}

  defp blank_to_nil(value) when is_binary(value) and value != "", do: value
  defp blank_to_nil(_value), do: nil

  defp org_id(conn), do: conn.assigns.current_scope.organization_id
  defp mission_id(conn), do: conn.assigns.current_mission.mission_id
end
