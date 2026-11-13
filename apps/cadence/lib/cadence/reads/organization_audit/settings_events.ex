defmodule Cadence.Reads.OrganizationAudit.SettingsEvents do
  @moduledoc """
  Settings changes for the organization audit (`kind: "config"`): one entry per saved revision
  of a section, for the organization's defaults (`mission_id` nil) or a mission's override.

  The per-field migration (`Cadence.Management.SettingsOverrideMigration`) may rewrite several
  of a mission's sections. Those revisions make one entry for the mission (ux), by the system
  (`actor` nil), with no target, at its last write.
  """

  alias Cadence.Platform.ScopedSettings

  @settings [
    {"cadence.governance", "Governance"},
    {"commanding.defaults", "Commanding"},
    {"cadence.configuration", "Configuration"},
    {"cadence.pass_review", "Pass review"}
  ]

  @spec list(binary(), binary() | nil, map() | nil) :: [map()]
  def list(organization_id, mission_id, mission) do
    entries =
      for {section, title} <- @settings,
          entry <- ScopedSettings.history(organization_id, mission_id, section) do
        {:ok, at, _offset} = DateTime.from_iso8601(entry.saved_at)
        Map.merge(entry, %{at: at, section: section, title: title})
      end

    {migrated, changed} = Enum.split_with(entries, &is_map(&1.migration))
    where = if mission_id, do: "", else: " (organization default)"

    Enum.map(changed, &changed(&1, where, mission)) ++ migrated(migrated, mission_id, mission)
  end

  defp changed(entry, where, mission) do
    %{
      id: "config:settings:#{entry.section}:#{DateTime.to_unix(entry.at, :microsecond)}",
      at: entry.at,
      actor: %{kind: "user", id: nil, name: entry.actor},
      kind: "config",
      action: "Changed #{entry.title} settings#{where}",
      target: %{kind: "settings", id: entry.section, label: entry.title},
      mission: mission,
      reason: nil
    }
  end

  defp migrated([], _mission_id, _mission), do: []

  defp migrated(entries, mission_id, mission) do
    at = entries |> Enum.map(& &1.at) |> Enum.max(DateTime)
    governance_kept? = Enum.any?(entries, &(&1.migration["governance_kept"] == true))

    [
      %{
        id: "config:settings_migration:#{mission_id}:#{DateTime.to_unix(at, :microsecond)}",
        at: at,
        actor: nil,
        kind: "config",
        action: ScopedSettings.migration_note(governance_kept?),
        target: nil,
        mission: mission,
        reason: nil
      }
    ]
  end
end
