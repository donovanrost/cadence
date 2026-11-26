defmodule Cadence.Management.Providers.ProviderAccountDetailTest do
  @moduledoc "PA2 grant rows (setup.md §L13): the mission name is always a string."
  use ExUnit.Case, async: true

  alias Cadence.Management.Providers.ProviderAccountDetail

  defp grant(mission_id),
    do: %{
      provider_account_grant_id: "pag-1",
      version: 2,
      mission_id: mission_id,
      lifecycle_state: :active,
      restrictions: %{},
      grant_reason: nil,
      granted_by: nil,
      granted_at: ~U[2026-11-13 00:00:00Z],
      revoked_by: nil,
      revoked_at: nil,
      revoke_reason: nil
    }

  test "a known mission reads its name" do
    assert %{mission: %{id: "m-1", name: "Earendil"}} =
             ProviderAccountDetail.grant_row(grant("m-1"), %{"m-1" => "Earendil"}, %{})
  end

  test "a mission with no name on record reads as its id, never null" do
    assert %{mission: %{id: "m-gone", name: "m-gone"}} =
             ProviderAccountDetail.grant_row(grant("m-gone"), %{"m-1" => "Earendil"}, %{})
  end
end
