defmodule Cadence.SpacecraftStore.Overrides do
  @moduledoc """
  Per-spacecraft overrides of profile values (`docs/apogee/domain/profile-routing.md` §2.3).

  Paths are profile schema paths marked overridable (`Cadence.SpacecraftType.Schema`), plus the
  routing paths `routing.<rule_id>.excluded_stations` (list of station ids) and
  `routing.<rule_id>.enabled` (boolean). Values are stored wrapped as `%{"value" => term}`.
  "Since rN" comes from the change-set ledger, not from this table.
  """

  import Ecto.Query

  alias Cadence.Repo
  alias Cadence.SpacecraftStore.OverrideRow
  alias Cadence.SpacecraftType.Schema

  @routing ~r/\Arouting\.[A-Za-z0-9][A-Za-z0-9_.:-]*\.(excluded_stations|enabled)\z/

  @type override :: %{
          value: term(),
          reason: String.t() | nil,
          set_by: map() | nil,
          set_at: DateTime.t()
        }

  @doc "Whether a path may be overridden."
  @spec overridable?(String.t()) :: boolean()
  # D3 (#544): composition_id is the per-craft pin, a change-set path only. It isn't a schema
  # field, so the console's kind editor shows no raw id field before its reads move (D2c).
  def overridable?(path) when is_binary(path) do
    Regex.match?(@routing, path) or path == "composition_id" or path in schema_paths()
  end

  def overridable?(_path), do: false

  @spec list(String.t(), String.t(), [String.t()]) :: %{String.t() => %{String.t() => override()}}
  def list(organization_id, mission_id, spacecraft_ids) when is_list(spacecraft_ids) do
    OverrideRow
    |> where(
      [o],
      o.organization_id == ^organization_id and o.mission_id == ^mission_id and
        o.spacecraft_id in ^spacecraft_ids
    )
    |> Repo.all()
    |> Enum.group_by(& &1.spacecraft_id)
    |> Map.new(fn {id, rows} -> {id, Map.new(rows, &{&1.path, view(&1)})} end)
  end

  @doc "Sets (or replaces) one override."
  @spec put(String.t(), String.t(), String.t(), String.t(), term(), map()) ::
          {:ok, override()} | {:error, term()}
  def put(organization_id, mission_id, spacecraft_id, path, value, attrs \\ %{}) do
    if overridable?(path) do
      row = %OverrideRow{
        organization_id: organization_id,
        mission_id: mission_id,
        spacecraft_id: spacecraft_id,
        path: path,
        value: %{"value" => value},
        reason: Map.get(attrs, :reason),
        set_by: Map.get(attrs, :set_by),
        set_at: DateTime.utc_now()
      }

      row
      |> Repo.insert(
        on_conflict: {:replace, [:value, :reason, :set_by, :set_at]},
        conflict_target: [:mission_id, :spacecraft_id, :path]
      )
      |> case do
        {:ok, row} -> {:ok, view(row)}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :path_not_overridable}
    end
  end

  @doc "Removes one override (reset to the profile value)."
  @spec delete(String.t(), String.t(), String.t(), String.t()) :: :ok
  def delete(organization_id, mission_id, spacecraft_id, path) do
    OverrideRow
    |> where(
      [o],
      o.organization_id == ^organization_id and o.mission_id == ^mission_id and
        o.spacecraft_id == ^spacecraft_id and o.path == ^path
    )
    |> Repo.delete_all()

    :ok
  end

  defp schema_paths do
    for section <- Schema.sections(), field <- section.fields, field.overridable, do: field.path
  end

  defp view(%OverrideRow{} = row) do
    %{
      value: Map.get(row.value || %{}, "value"),
      reason: row.reason,
      set_by: row.set_by,
      set_at: row.set_at
    }
  end
end
