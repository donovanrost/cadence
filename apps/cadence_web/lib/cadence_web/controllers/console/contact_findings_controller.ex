defmodule CadenceWeb.Console.ContactFindingsController do
  @moduledoc """
  M22 (Contacts D4 "Needs a decision"): `GET /contact-findings`. Station double-bookings,
  bookings in station outages and spacecraft coverage gaps across live bookings. Contract:
  docs/apogee/api/contacts.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Reads.ContactFindings
  alias CadenceWeb.Console.{ConfigJSON, Problem, WindowParams}

  @default_span_s 6 * 3600
  @max_span_s 7 * 24 * 3600

  def index(conn, params) do
    with {:ok, window} <- WindowParams.parse(forward(params), max_span_s: @max_span_s),
         {:ok, max_gap_s} <- max_gap(params["max_gap_s"]) do
      findings =
        ContactFindings.load(
          conn.assigns.current_scope.organization_id,
          conn.assigns.current_mission.mission_id,
          window.from,
          window.to,
          max_gap_s: max_gap_s
        )

      json(conn, %{data: ConfigJSON.encode(findings)})
    else
      {:error, {:invalid_params, details}} -> Problem.respond(conn, :invalid_params, details)
    end
  end

  # Findings look forward: by default from now for six hours.
  defp forward(params) do
    from =
      case DateTime.from_iso8601(params["from"] || "") do
        {:ok, from, _offset} -> from
        _missing -> DateTime.utc_now() |> DateTime.truncate(:millisecond)
      end

    params
    |> Map.put_new("from", DateTime.to_iso8601(from))
    |> Map.put_new("to", from |> DateTime.add(@default_span_s) |> DateTime.to_iso8601())
  end

  defp max_gap(nil), do: {:ok, 4 * 3600}

  defp max_gap(value) do
    case Integer.parse(to_string(value)) do
      {n, ""} when n >= 600 and n <= 7 * 24 * 3600 ->
        {:ok, n}

      _invalid ->
        {:error, {:invalid_params, %{max_gap_s: "must be seconds between 600 and 604800"}}}
    end
  end
end
