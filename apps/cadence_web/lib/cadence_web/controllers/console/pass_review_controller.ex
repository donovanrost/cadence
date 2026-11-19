defmodule CadenceWeb.Console.PassReviewController do
  @moduledoc """
  K3 "Close the books" (scheduling S9, DECISIONS #47/#48) over
  `Cadence.Reads.PassReview`. Contract: docs/apogee/api/contacts.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Reads.PassReview
  alias CadenceWeb.Console.{Problem, WindowParams}

  @spans %{"day" => 1, "week" => 7, "month" => 30}
  @outcomes ~w(realized partial missed failed canceled pending_report)
  @max_limit 500

  def summary(conn, params) do
    with {:ok, window} <- window(params),
         {:ok, summary} <-
           PassReview.summary(scope(conn), mission(conn), window.from, window.to,
             plan: blank(params["plan"])
           ) do
      json(conn, %{data: encode(Map.merge(summary, %{from: window.from, to: window.to}))})
    else
      error -> problem(conn, error)
    end
  end

  def rows(conn, params) do
    with {:ok, window} <- window(params),
         {:ok, filters} <- filters(params),
         {:ok, page} <-
           PassReview.rows(scope(conn), mission(conn), window.from, window.to, filters) do
      json(conn, %{
        data:
          encode(%{
            from: window.from,
            to: window.to,
            rows: page.rows,
            total: page.total,
            disputable: page.disputable,
            next_cursor: page.next_cursor
          }),
        meta: %{next_cursor: page.next_cursor}
      })
    else
      error -> problem(conn, error)
    end
  end

  def daily(conn, params) do
    params = Map.put_new(params, "span", "month")

    with {:ok, window} <- window(params),
         {:ok, daily} <-
           PassReview.daily(scope(conn), mission(conn), window.from, window.to,
             plan: blank(params["plan"])
           ) do
      json(conn, %{data: encode(Map.merge(daily, %{from: window.from, to: window.to}))})
    else
      error -> problem(conn, error)
    end
  end

  # `from`/`to` (ISO-8601), or `day` (YYYY-MM-DD, default today UTC) + `span` (day | week | month,
  # default day) ending at the close of that day. At most 31 days.
  defp window(%{"from" => _from} = params),
    do: WindowParams.parse(params, max_span_s: 31 * 86_400)

  defp window(params) do
    with {:ok, days} <- span(params["span"] || "day"),
         {:ok, day} <- day(params["day"]) do
      to = DateTime.new!(Date.add(day, 1), ~T[00:00:00.000], "Etc/UTC")
      {:ok, %{from: DateTime.add(to, -days * 86_400), to: to}}
    end
  end

  defp span(value) do
    case Map.fetch(@spans, value) do
      {:ok, days} -> {:ok, days}
      :error -> {:error, {:invalid_params, %{"span" => "must be day, week or month"}}}
    end
  end

  defp day(nil), do: {:ok, Date.utc_today()}

  defp day(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      _error -> {:error, {:invalid_params, %{"day" => "must be YYYY-MM-DD"}}}
    end
  end

  defp filters(params) do
    outcomes = params |> Map.get("outcome", "") |> String.split(",", trim: true)

    with :ok <- known_outcomes(outcomes),
         {:ok, limit} <- int(params["limit"], 50, 1..@max_limit, "limit"),
         {:ok, offset} <- int(params["cursor"], 0, 0..1_000_000, "cursor") do
      {:ok,
       %{
         outcome: outcomes,
         station: blank(params["station"]),
         spacecraft_id: blank(params["spacecraft_id"]),
         plan: blank(params["plan"]),
         limit: limit,
         offset: offset
       }}
    end
  end

  defp known_outcomes(outcomes) do
    if Enum.all?(outcomes, &(&1 in @outcomes)),
      do: :ok,
      else:
        {:error,
         {:invalid_params,
          %{"outcome" => "must be a comma list of #{Enum.join(@outcomes, ", ")}"}}}
  end

  defp int(nil, default, _range, _key), do: {:ok, default}

  defp int(value, _default, range, key) do
    case Integer.parse(to_string(value)) do
      {n, ""} ->
        if n in range,
          do: {:ok, n},
          else: {:error, {:invalid_params, %{key => "is out of range"}}}

      _other ->
        {:error, {:invalid_params, %{key => "must be an integer"}}}
    end
  end

  defp problem(conn, {:error, {:invalid_params, details}}),
    do: Problem.respond(conn, :invalid_params, details)

  defp problem(conn, {:error, :forbidden}), do: Problem.respond(conn, :forbidden)

  defp encode(%DateTime{} = at), do: at
  defp encode(%Date{} = date), do: date
  defp encode(%Decimal{} = value), do: Decimal.to_float(value)
  defp encode(%_{} = struct), do: struct |> Map.from_struct() |> encode()
  defp encode(map) when is_map(map), do: Map.new(map, fn {key, value} -> {key, encode(value)} end)
  defp encode(list) when is_list(list), do: Enum.map(list, &encode/1)
  defp encode(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> encode()

  defp encode(atom) when is_atom(atom) and atom not in [nil, true, false],
    do: Atom.to_string(atom)

  defp encode(value), do: value

  defp blank(value) when is_binary(value) and value != "", do: value
  defp blank(_value), do: nil

  defp scope(conn), do: conn.assigns.current_scope
  defp mission(conn), do: conn.assigns.current_mission.mission_id
end
