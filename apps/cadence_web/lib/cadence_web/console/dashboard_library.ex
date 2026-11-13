defmodule CadenceWeb.Console.DashboardLibrary do
  @moduledoc """
  D21/D22 (fe-ops, docs/apogee/plans/dashboards-library.md): library reads over
  `Reads.Dashboards.LibraryRows`; writes over `LibraryAuthoring` (create, new version) and
  `LibraryLifecycle` (rename, retire; Q6/Q10). Every write guards on `expected_version`, the
  item's latest version.
  """

  alias Cadence.Dashboards.{LibraryAuthoring, LibraryLifecycle}
  alias Cadence.Reads.Dashboards.LibraryRows

  def list(scope, mission, params), do: LibraryRows.list(scope, mission, params)
  def get(scope, mission, id, params), do: LibraryRows.get(scope, mission, id, params["version"])

  def create(scope, mission, body) do
    input = %{
      "name" => body["name"],
      "description" => body["description"] || "",
      "change_summary" => body["summary"] || "",
      "widget_json" => body["definition_json"]
    }

    case LibraryAuthoring.execute(scope, mission, "create_item", input) do
      {:ok, receipt} -> {:ok, %{id: receipt.item_id, version: receipt.library_version}}
      error -> error(scope, mission, nil, error)
    end
  end

  def add_version(scope, mission, id, body) do
    input = %{
      "item_id" => id,
      "expected_version" => body["expected_version"],
      "change_summary" => body["summary"] || "",
      "widget_json" => body["definition_json"]
    }

    case LibraryAuthoring.execute(scope, mission, "add_version", input) do
      {:ok, receipt} -> {:ok, %{version: receipt.library_version}}
      error -> error(scope, mission, id, error)
    end
  end

  def update(scope, mission, id, body) do
    with {:ok, expected} <- expected(body["expected_version"]),
         {:ok, _item} <-
           LibraryLifecycle.update_item(
             scope,
             mission,
             id,
             Map.take(body, ~w(name description)),
             expected,
             body["expected_updated_at"]
           ) do
      with {:ok, read} <- LibraryRows.get(scope, mission, id, nil), do: {:ok, read.item}
    else
      error -> error(scope, mission, id, error)
    end
  end

  def retire(scope, mission, id, params) do
    with {:ok, expected} <- expected(params["expected_version"]) do
      case LibraryLifecycle.retire_item(
             scope,
             mission,
             id,
             expected,
             params["expected_updated_at"]
           ) do
        :ok -> :ok
        {:ok, _audited} -> :ok
        error -> error(scope, mission, id, error)
      end
    end
  end

  defp expected(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp expected(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n > 0 ->
        {:ok, n}

      _invalid ->
        {:error, {:invalid_params, %{expected_version: "must be the item's latest version"}}}
    end
  end

  defp expected(_value),
    do: {:error, {:invalid_params, %{expected_version: "must be the item's latest version"}}}

  defp error(_scope, _mission, _id, {:error, {:invalid_params, _}} = error), do: error

  defp error(_scope, _mission, _id, {:error, {:library_item_changed, latest}}),
    do: {:error, {:library_item_changed, %{latest_version: latest}}}

  defp error(_scope, _mission, _id, {:error, {:library_item_in_use, details}}),
    do: {:error, {:library_item_in_use, details}}

  # add_version's conflict doesn't carry the latest version: read it.
  defp error(scope, mission, id, {:error, :conflict}) do
    case LibraryRows.get(scope, mission, id, nil) do
      {:ok, read} ->
        {:error, {:library_item_changed, %{latest_version: read.item.latest_version}}}

      _gone ->
        {:error, :library_item_not_found}
    end
  end

  defp error(_scope, _mission, _id, {:error, reason}) when reason in [:not_found, :unavailable],
    do: {:error, :library_item_not_found}

  defp error(_scope, _mission, _id, {:error, :invalid_widget}),
    do: {:error, {:invalid_params, %{definition_json: "isn't a valid widget definition"}}}

  defp error(_scope, _mission, _id, {:error, :invalid_input}),
    do:
      {:error,
       {:invalid_params,
        %{request: "name 1–120 characters; definition_json a widget definition as JSON text"}}}

  defp error(_scope, _mission, _id, {:error, reason}), do: {:error, reason}
end
