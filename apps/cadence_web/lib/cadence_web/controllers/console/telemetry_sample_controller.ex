defmodule CadenceWeb.Console.TelemetrySampleController do
  @moduledoc """
  `GET /api/v1/missions/:mission_id/telemetry/samples/:sample_id` (§11c(D) D1): one
  telemetry sample for Investigate's Sample aside (`Cadence.Reads.ConsoleSample`). Query:
  `point_id` and `spacecraft_id` (required), `receipt_time` (ISO-8601, optional: the exact match),
  `at` (ISO-8601, optional: the sample's generation time, bounding the search to ±60 s).
  Answers `{data: {status, sample}}`. Contract: docs/apogee/api/ops.md §One sample.
  """

  use CadenceWeb, :controller

  alias Cadence.Reads.ConsoleSample
  alias CadenceWeb.Console.Problem

  def show(conn, %{"sample_id" => sample_id} = params) do
    case selection(sample_id, params) do
      {:ok, selection} ->
        result =
          ConsoleSample.load(
            conn.assigns.current_scope,
            conn.assigns.current_mission.mission_id,
            selection
          )

        json(conn, %{data: result})

      {:error, details} ->
        Problem.respond(conn, :invalid_params, details)
    end
  end

  defp selection(sample_id, params) do
    errors =
      %{}
      |> required(params, "point_id")
      |> required(params, "spacecraft_id")

    {errors, receipt_time} = time(errors, params, "receipt_time")
    {errors, at} = time(errors, params, "at")

    if errors == %{},
      do:
        {:ok,
         %{
           sample_id: sample_id,
           point_id: params["point_id"],
           spacecraft_id: params["spacecraft_id"],
           receipt_time: receipt_time,
           at: at
         }},
      else: {:error, errors}
  end

  defp time(errors, params, key) do
    case parse_time(params[key]) do
      {:ok, value} -> {errors, value}
      :error -> {Map.put(errors, key, "must be an ISO-8601 time"), nil}
    end
  end

  defp required(errors, params, key) do
    case params[key] do
      value when is_binary(value) and value != "" -> errors
      _missing -> Map.put(errors, key, "is required")
    end
  end

  defp parse_time(nil), do: {:ok, nil}
  defp parse_time(""), do: {:ok, nil}

  defp parse_time(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> {:ok, at}
      _invalid -> :error
    end
  end

  defp parse_time(_value), do: :error
end
