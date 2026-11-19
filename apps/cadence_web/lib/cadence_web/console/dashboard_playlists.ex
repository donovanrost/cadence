defmodule CadenceWeb.Console.DashboardPlaylists do
  @moduledoc """
  D23/D24 (dashboards, docs/apogee/plans/dashboards-slice6.md): playlist reads over
  `Reads.Dashboards.PlaylistRows`, writes over `PlaylistAuthoring` (Q6). A PATCH carries the row's
  `updated_at` as `expected_updated_at`; a stale one answers the current row.
  """

  alias Cadence.Dashboards.PlaylistAuthoring
  alias Cadence.Reads.Dashboards.PlaylistRows

  @fields ~w(name description dashboard_ids dwell_seconds wallboard_mode)

  def list(scope, mission, params), do: PlaylistRows.list(scope, mission, params["q"])
  def get(scope, mission, id), do: PlaylistRows.get(scope, mission, id)

  def create(scope, mission, body) do
    input = body |> Map.take(@fields) |> Map.put_new("description", "")

    case PlaylistAuthoring.create(scope, mission, input) do
      {:ok, created} -> {:ok, %{id: created.id}}
      error -> error(error)
    end
  end

  def update(scope, mission, id, body) do
    with {:ok, expected} <- expected(body["expected_updated_at"]) do
      case PlaylistAuthoring.update(scope, mission, id, Map.take(body, @fields), expected) do
        {:ok, playlist} -> {:ok, %{id: playlist.dashboard_playlist_id}}
        error -> error(error)
      end
    end
  end

  def delete(scope, mission, id) do
    case PlaylistAuthoring.delete(scope, mission, id) do
      {:error, _reason} = error -> error(error)
      _audited -> :ok
    end
  end

  defp expected(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> {:ok, at}
      _invalid -> invalid(%{expected_updated_at: "must be the playlist's updated_at"})
    end
  end

  defp expected(_value), do: invalid(%{expected_updated_at: "must be the playlist's updated_at"})

  defp error({:error, :not_found}), do: {:error, :playlist_not_found}

  defp error({:error, {:stale, current}}),
    do: {:error, {:version_conflict, %{current: PlaylistRows.detail(current)}}}

  defp error({:error, {:invalid_dashboard, ids}}),
    do: invalid(%{dashboard_ids: "aren't all active dashboards of this mission", unknown: ids})

  defp error({:error, :invalid_dashboard}),
    do: invalid(%{dashboard_ids: "aren't all active dashboards of this mission"})

  defp error({:error, :invalid_input}),
    do:
      invalid(%{
        playlist:
          "name 1–120 characters, dwell_seconds 5–900, 1–100 dashboards, wallboard_mode a boolean"
      })

  defp error({:error, reason}), do: {:error, reason}

  defp invalid(details), do: {:error, {:invalid_params, details}}
end
