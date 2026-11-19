defmodule CadenceWeb.Console.EventController do
  @moduledoc """
  Mission event log (`GET .../events`), density (`GET .../events/density`) and one event
  (`GET .../events/:event_id`, U69 A8b) for Investigate B2 and Timeline. Contract: docs/apogee/api/ops.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Reads.EventLog
  alias Cadence.Reads.EventLog.RawKinds
  alias CadenceWeb.Console.{ConfigJSON, Problem, WindowParams}

  @day_s 86_400

  def index(conn, params) do
    with {:ok, window} <- WindowParams.parse(params, default_span_s: @day_s, max_span_s: nil),
         {:ok, kinds} <- kinds(params["kind"]),
         {:ok, raw_kinds} <- raw_kinds(params["raw_kind"]),
         {:ok, floor} <- severity_floor(params["severity_at_least"]),
         {:ok, limit} <- int(params["limit"], :limit, 200, 1..500),
         {:ok, plane} <- int(params["plane"], :plane, nil, 0..10_000),
         {:ok, page} <-
           EventLog.page(org_id(conn), mission_id(conn), %{
             from: window.from,
             to: window.to,
             spacecraft_id: window.spacecraft_id,
             plane: plane,
             kinds: kinds,
             raw_kinds: raw_kinds,
             severity_at_least: floor,
             limit: limit,
             cursor: params["cursor"]
           }) do
      json(conn, %{
        data: ConfigJSON.encode(%{from: window.from, to: window.to, events: page.events}),
        meta: %{next_cursor: page.next_cursor}
      })
    else
      error -> error(conn, error)
    end
  end

  def density(conn, params) do
    with {:ok, window} <-
           WindowParams.parse(params, default_span_s: @day_s, max_span_s: 31 * @day_s),
         {:ok, kinds} <- kinds(params["kind"]),
         {:ok, raw_kinds} <- raw_kinds(params["raw_kind"]),
         {:ok, floor} <- severity_floor(params["severity_at_least"]),
         {:ok, bucket_s} <- int(params["bucket_s"], :bucket_s, default_bucket(window), 60..@day_s),
         {:ok, plane} <- int(params["plane"], :plane, nil, 0..10_000) do
      density =
        EventLog.density(org_id(conn), mission_id(conn), %{
          from: window.from,
          to: window.to,
          spacecraft_id: window.spacecraft_id,
          plane: plane,
          kinds: kinds,
          raw_kinds: raw_kinds,
          severity_at_least: floor,
          bucket_s: bucket_s
        })

      json(conn, %{data: ConfigJSON.encode(density)})
    else
      error -> error(conn, error)
    end
  end

  @doc "U69 A9b: the raw kinds in the window with their console kind and count (a picker)."
  def raw_kind_list(conn, params) do
    case WindowParams.parse(params, default_span_s: @day_s, max_span_s: 31 * @day_s) do
      {:ok, window} ->
        kinds = RawKinds.list(org_id(conn), mission_id(conn), window.from, window.to)

        json(conn, %{
          data: ConfigJSON.encode(%{from: window.from, to: window.to, raw_kinds: kinds})
        })

      error ->
        error(conn, error)
    end
  end

  # U69 A9a: caution = caution and critical.
  defp severity_floor(nil), do: {:ok, nil}
  defp severity_floor(""), do: {:ok, nil}
  defp severity_floor("caution"), do: {:ok, :caution}
  defp severity_floor("critical"), do: {:ok, :critical}

  defp severity_floor(_value),
    do: {:error, {:invalid_params, %{severity_at_least: "must be caution or critical"}}}

  defp raw_kinds(value) do
    case RawKinds.parse(value) do
      {:ok, patterns} -> {:ok, patterns}
      {:error, message} -> {:error, {:invalid_params, %{raw_kind: message}}}
    end
  end

  defp kinds(nil), do: {:ok, nil}

  defp kinds(value) when is_binary(value) do
    kinds = value |> String.split(",", trim: true) |> Enum.map(&String.trim/1)

    if Enum.all?(kinds, &(&1 in EventLog.kinds())),
      do: {:ok, kinds},
      else:
        {:error,
         {:invalid_params,
          %{kind: "must be a comma list of #{Enum.join(EventLog.kinds(), ", ")}"}}}
  end

  defp kinds(_value), do: {:error, {:invalid_params, %{kind: "must be a comma list"}}}

  defp int(nil, _key, default, _range), do: {:ok, default}

  defp int(value, key, _default, range) do
    case Integer.parse(to_string(value)) do
      {n, ""} ->
        if n in range,
          do: {:ok, n},
          else: {:error, {:invalid_params, %{key => "is out of range"}}}

      _other ->
        {:error, {:invalid_params, %{key => "must be an integer"}}}
    end
  end

  # About 96 buckets over the window, at least a minute.
  defp default_bucket(window), do: max(div(DateTime.diff(window.to, window.from), 96), 60)

  @doc "U69 A8b: one event by its id (a Timeline permalink), in the row shape."
  def show(conn, %{"event_id" => id}) do
    case EventLog.fetch(org_id(conn), mission_id(conn), id) do
      {:ok, event} -> json(conn, %{data: ConfigJSON.encode(%{event: event})})
      {:error, :event_not_found} -> Problem.respond(conn, :event_not_found)
    end
  end

  defp error(conn, {:error, {:invalid_params, details}}),
    do: Problem.respond(conn, :invalid_params, details)

  defp error(conn, {:error, :invalid_cursor}),
    do: Problem.respond(conn, :invalid_params, %{cursor: "is not a valid cursor"})

  defp org_id(conn), do: conn.assigns.current_scope.organization_id
  defp mission_id(conn), do: conn.assigns.current_mission.mission_id
end
