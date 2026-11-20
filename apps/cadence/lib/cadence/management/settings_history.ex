defmodule Cadence.Management.SettingsHistory do
  @moduledoc """
  A settings section's History for the console (#470, #146 rule C1): who saved each revision,
  named live from its stored `actor_id`, by display name only while they're an active member of
  the organization (`MemberNames.members/2`), else `nil`. Never the stored `actor_name`, which is
  `display_name || email` in rows saved before #470, and never an id.
  """

  alias Cadence.Accounts.MemberNames
  alias Cadence.Platform.ScopedSettings

  @spec list(binary(), binary() | nil, binary()) :: [map()]
  def list(organization_id, mission_id, section_id) do
    entries = ScopedSettings.history(organization_id, mission_id, section_id)

    names =
      MemberNames.members(
        organization_id,
        entries |> Enum.map(& &1.actor_id) |> Enum.filter(&is_binary/1)
      )

    Enum.map(entries, fn entry ->
      entry |> Map.delete(:actor_id) |> Map.put(:actor, Map.get(names, entry.actor_id))
    end)
  end
end
