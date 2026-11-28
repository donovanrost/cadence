defmodule CadenceWeb.Console.ElementSetController do
  @moduledoc """
  Spacecraft orbits as SGP4 element sets (#889, slice 1 of #732). Contract:
  docs/apogee/api/element-sets.md.

    * `POST /missions/:mission_id/spacecraft/:spacecraft_id/element-sets`: one TLE or OMM; 201 when
      stored, 200 when the same set was already stored.
    * `POST /missions/:mission_id/element-sets`: up to 1,000 `{spacecraft_id, tle | omm}`, each
      answered on its own.
    * `GET .../spacecraft/:spacecraft_id/element-sets`: history, newest epoch first, cursor-paged.
    * `GET .../spacecraft/:spacecraft_id/element-sets/current`: the current set, or `data: null`.

  Writes need `:manage_mission`. A service identity reaches none of these (they aren't listed in
  `CadenceWeb.Console.ServiceAccess`); the catalog feed will be the first to opt in.
  """

  use CadenceWeb, :controller

  alias Cadence.Auth.Policy
  alias Cadence.GroundNetworks.ElementSets
  alias Cadence.SpacecraftStore
  alias CadenceWeb.Console.{ElementSetJSON, Problem}
  alias CadenceWeb.ControlPlaneAccess

  def create(conn, %{"spacecraft_id" => spacecraft_id} = params) do
    with :ok <- authorize(conn),
         :ok <- ensure_spacecraft(conn, spacecraft_id),
         {:ok, input} <- input(params) do
      item = %{spacecraft_id: spacecraft_id, input: input}
      {:ok, [result]} = submit(conn, [item])
      created(conn, result)
    else
      error -> failure(conn, error)
    end
  end

  def bulk(conn, %{"element_sets" => items}) when is_list(items) do
    with :ok <- authorize(conn),
         :ok <- bounded(items) do
      shaped = Enum.map(items, &item/1)
      valid = for {:ok, item} <- shaped, do: item

      {:ok, answers} = submit(conn, valid)
      json(conn, %{data: bulk_results(conn, shaped, answers)})
    else
      error -> failure(conn, error)
    end
  end

  def bulk(conn, _params),
    do: Problem.respond(conn, :invalid_params, %{field: "element_sets", reason: "must be a list"})

  def index(conn, %{"spacecraft_id" => spacecraft_id} = params) do
    with :ok <- ensure_spacecraft(conn, spacecraft_id),
         {:ok, limit} <- limit(params["limit"]),
         {:ok, page} <-
           ElementSets.history(org(conn), mission(conn), spacecraft_id, params["cursor"], limit) do
      names = ElementSetJSON.names(org(conn), page.items)

      json(conn, %{
        data: Enum.map(page.items, &ElementSetJSON.element_set(&1, names)),
        meta: %{next_cursor: page.next_cursor}
      })
    else
      error -> failure(conn, error)
    end
  end

  def current(conn, %{"spacecraft_id" => spacecraft_id}) do
    case ensure_spacecraft(conn, spacecraft_id) do
      :ok -> json(conn, %{data: current_set(conn, spacecraft_id)})
      error -> failure(conn, error)
    end
  end

  defp current_set(conn, spacecraft_id) do
    case ElementSets.current(org(conn), mission(conn), spacecraft_id) do
      nil -> nil
      row -> encode(conn, row)
    end
  end

  defp submit(_conn, []), do: {:ok, []}

  defp submit(conn, items),
    do: ElementSets.submit(org(conn), mission(conn), items, write_opts(conn))

  defp created(conn, {:created, row}),
    do:
      conn |> put_status(:created) |> json(%{data: encode(conn, row), meta: %{result: "created"}})

  defp created(conn, {:unchanged, row}),
    do: json(conn, %{data: encode(conn, row), meta: %{result: "unchanged"}})

  defp created(conn, {:refused, reason, details}),
    do: Problem.respond(conn, ElementSetJSON.problem(reason), details)

  defp encode(conn, row), do: ElementSetJSON.element_set(row, names(conn, [row]))
  defp names(conn, rows), do: ElementSetJSON.names(org(conn), rows)

  # Items that failed their shape check never reached the domain; the rest answer in order.
  defp bulk_results(conn, shaped, answers) do
    rows = for {status, row} <- answers, status in [:created, :unchanged], do: row
    names = names(conn, rows)

    {results, []} =
      shaped
      |> Enum.with_index()
      |> Enum.map_reduce(answers, fn
        {{:ok, item}, index}, [answer | rest] ->
          {result(index, item.spacecraft_id, answer, names), rest}

        {{:error, spacecraft_id, details}, index}, rest ->
          {result(index, spacecraft_id, {:refused, :invalid_params, details}, names), rest}
      end)

    %{results: results, counts: counts(results)}
  end

  defp result(index, spacecraft_id, {status, row}, names) when status in [:created, :unchanged],
    do: %{
      index: index,
      spacecraft_id: spacecraft_id,
      result: Atom.to_string(status),
      element_set: ElementSetJSON.element_set(row, names)
    }

  defp result(index, spacecraft_id, {:refused, reason, details}, _names),
    do: %{
      index: index,
      spacecraft_id: spacecraft_id,
      result: "refused",
      error: ElementSetJSON.refusal(reason, details)
    }

  defp counts(results) do
    base = %{created: 0, unchanged: 0, refused: 0}

    Enum.reduce(
      results,
      base,
      &Map.update!(&2, String.to_existing_atom(&1.result), fn n -> n + 1 end)
    )
  end

  defp item(%{"spacecraft_id" => spacecraft_id} = raw) when is_binary(spacecraft_id) do
    case input(raw) do
      {:ok, input} -> {:ok, %{spacecraft_id: spacecraft_id, input: input}}
      {:error, {:invalid_param, details}} -> {:error, spacecraft_id, details}
    end
  end

  defp item(_raw),
    do: {:error, nil, %{field: "spacecraft_id", reason: "is required"}}

  defp input(%{"tle" => tle} = params) when is_binary(tle) and not is_map_key(params, "omm"),
    do: {:ok, {:tle, tle}}

  defp input(%{"omm" => omm} = params)
       when (is_binary(omm) or is_map(omm)) and not is_map_key(params, "tle"),
       do: {:ok, {:omm, omm}}

  defp input(_params),
    do:
      {:error,
       {:invalid_param,
        %{field: "tle", reason: "send exactly one of tle (text) or omm (object or KVN text)"}}}

  defp bounded(items) do
    cond do
      items == [] -> {:error, {:invalid_param, %{field: "element_sets", reason: "is empty"}}}
      length(items) > ElementSets.max_batch() -> {:error, :element_set_batch_too_large}
      true -> :ok
    end
  end

  defp limit(nil), do: {:ok, nil}

  defp limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n in 1..200 -> {:ok, n}
      _other -> {:error, {:invalid_param, %{field: "limit", reason: "must be 1 to 200"}}}
    end
  end

  defp limit(_value),
    do: {:error, {:invalid_param, %{field: "limit", reason: "must be 1 to 200"}}}

  defp authorize(conn) do
    Policy.authorize(conn.assigns.current_scope, :manage_mission, %{
      organization_id: org(conn),
      mission_id: mission(conn)
    })
  end

  defp ensure_spacecraft(conn, spacecraft_id) do
    with {:ok, _spacecraft} <-
           SpacecraftStore.fetch_spacecraft(org(conn), mission(conn), spacecraft_id),
         do: :ok
  end

  defp write_opts(conn) do
    scope = conn.assigns.current_scope

    [
      actor: ControlPlaneAccess.actor_document(scope),
      source: if(scope.actor_kind == :service, do: "api", else: "manual")
    ]
  end

  defp failure(conn, {:error, {:invalid_param, details}}),
    do: Problem.respond(conn, :invalid_params, details)

  defp failure(conn, {:error, :invalid_cursor}),
    do:
      Problem.respond(conn, :invalid_params, %{field: "cursor", reason: "is not a valid cursor"})

  defp failure(conn, {:error, reason}) when is_atom(reason), do: Problem.respond(conn, reason)

  defp org(conn), do: conn.assigns.current_scope.organization_id
  defp mission(conn), do: conn.assigns.current_mission.mission_id
end
