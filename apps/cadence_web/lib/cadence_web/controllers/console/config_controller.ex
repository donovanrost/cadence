defmodule CadenceWeb.Console.ConfigController do
  @moduledoc """
  Mission change sets and configuration revisions under
  `/api/console/v1/missions/:mission_id/config`: a thin pass-through of
  `Cadence.Control.Configuration`. Contract: docs/apogee/api/changes.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Control.Configuration
  alias CadenceWeb.Console.{ConfigJSON, ConfigParams}

  def show(conn, _params) do
    with {:ok, current} <- Configuration.current(scope(conn), mission_id(conn)),
         {:ok, permissions} <- Configuration.permissions(scope(conn), mission_id(conn)) do
      ok(conn, Map.put(current, :permissions, permissions))
    end
    |> reply(conn)
  end

  def change_set(conn, %{"change_set_id" => id}),
    do: Configuration.change_set(scope(conn), mission_id(conn), id) |> wrap() |> reply(conn)

  def stage(conn, body) do
    with {:ok, attrs, ops} <- params(ConfigParams.stage(body)),
         {:ok, result} <- Configuration.stage(scope(conn), mission_id(conn), attrs, ops) do
      conn |> put_status(:created) |> ok(result)
    end
    |> reply(conn)
  end

  def withdraw(conn, %{"change_id" => id}),
    do: Configuration.withdraw(scope(conn), mission_id(conn), id) |> wrap() |> reply(conn)

  def discard(conn, %{"change_set_id" => id} = body) do
    with {:ok, version} <- params(ConfigParams.expected_version(body)),
         {:ok, result} <- Configuration.discard(scope(conn), mission_id(conn), id, version) do
      ok(conn, result)
    end
    |> reply(conn)
  end

  def preview_set(conn, %{"change_set_id" => id}),
    do: Configuration.preview(scope(conn), mission_id(conn), id) |> wrap() |> reply(conn)

  def preview_ops(conn, body) do
    with {:ok, ops} <- params(ConfigParams.ops(body)),
         {:ok, preview} <- Configuration.preview(scope(conn), mission_id(conn), {:ops, ops}) do
      ok(conn, preview)
    end
    |> reply(conn)
  end

  def rebase(conn, %{"op_id" => op_id} = body) do
    with {:ok, choice} <- params(ConfigParams.rebase_choice(body)),
         {:ok, result} <- Configuration.rebase(scope(conn), mission_id(conn), op_id, choice) do
      ok(conn, result)
    end
    |> reply(conn)
  end

  def submit(conn, %{"change_set_id" => id} = body) do
    with {:ok, submit} <- params(ConfigParams.submit(body)),
         {:ok, result} <- Configuration.submit(scope(conn), mission_id(conn), id, submit) do
      ok(conn, result)
    end
    |> reply(conn)
  end

  def review(conn, %{"change_set_id" => id} = body) do
    with {:ok, decision, review} <- params(ConfigParams.review(body)),
         {:ok, result} <-
           Configuration.review(scope(conn), mission_id(conn), id, decision, review) do
      ok(conn, result)
    end
    |> reply(conn)
  end

  def revisions(conn, params) do
    with {:ok, opts} <- params(ConfigParams.list_opts(params)),
         {:ok, revisions} <- Configuration.list_revisions(scope(conn), mission_id(conn), opts) do
      ok(conn, %{revisions: revisions})
    end
    |> reply(conn)
  end

  def revision(conn, %{"revision" => number}) do
    with {:ok, n} <- params(ConfigParams.revision_number(number)),
         {:ok, revision} <- Configuration.get_revision(scope(conn), mission_id(conn), n) do
      ok(conn, revision)
    end
    |> reply(conn)
  end

  def compare(conn, params) do
    with {:ok, from} <- params(ConfigParams.revision_number(params["from"])),
         {:ok, to} <- params(ConfigParams.revision_number(params["to"])),
         {:ok, entries} <- Configuration.compare(scope(conn), mission_id(conn), from, to) do
      ok(conn, %{from: from, to: to, entries: entries})
    end
    |> reply(conn)
  end

  defp ok(conn, data), do: {:sent, json(conn, %{data: ConfigJSON.encode(data)})}

  defp wrap({:ok, data}), do: {:data, data}
  defp wrap(other), do: other

  defp reply({:sent, conn}, _conn), do: conn
  defp reply({:data, data}, conn), do: json(conn, %{data: ConfigJSON.encode(data)})
  defp reply({:error, reason}, conn), do: ConfigJSON.error(conn, reason)

  defp params({:error, details}) when is_map(details), do: {:error, {:invalid_params, details}}
  defp params(ok), do: ok

  defp scope(conn), do: conn.assigns.current_scope
  defp mission_id(conn), do: conn.assigns.current_mission.mission_id
end
