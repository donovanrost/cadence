defmodule CadenceWeb.OpsDashboardShowLive.ContactScopePolicyTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.ContactScopePolicy

  test "valid_contact? accepts scheduled contacts" do
    assert ContactScopePolicy.valid_contact?(scope(), mission(), "contact-1",
             fetch_scheduled_contact: fn organization_id, mission_id, contact_id ->
               assert organization_id == "org-1"
               assert mission_id == "mission-1"
               assert contact_id == "contact-1"
               {:ok, %{contact_id: contact_id}}
             end,
             fetch_realized_contact: fn _organization_id, _mission_id, _contact_id ->
               raise "should not fetch realized contact"
             end
           )
  end

  test "valid_contact? accepts realized contacts when no scheduled contact exists" do
    assert ContactScopePolicy.valid_contact?(scope(), mission(), "contact-1",
             fetch_scheduled_contact: fn _organization_id, _mission_id, _contact_id ->
               {:error, :scheduled_contact_not_found}
             end,
             fetch_realized_contact: fn organization_id, mission_id, contact_id ->
               assert organization_id == "org-1"
               assert mission_id == "mission-1"
               assert contact_id == "contact-1"
               {:ok, %{contact_id: contact_id}}
             end
           )
  end

  test "valid_contact? rejects missing scheduled and realized contacts" do
    refute ContactScopePolicy.valid_contact?(scope(), mission(), "contact-1",
             fetch_scheduled_contact: fn _organization_id, _mission_id, _contact_id ->
               {:error, :scheduled_contact_not_found}
             end,
             fetch_realized_contact: fn _organization_id, _mission_id, _contact_id ->
               {:error, :realized_contact_not_found}
             end
           )
  end

  test "valid_contact? rejects scheduled lookup errors without fetching realized contacts" do
    refute ContactScopePolicy.valid_contact?(scope(), mission(), "contact-1",
             fetch_scheduled_contact: fn _organization_id, _mission_id, _contact_id ->
               {:error, :database_unavailable}
             end,
             fetch_realized_contact: fn _organization_id, _mission_id, _contact_id ->
               raise "should not fetch realized contact"
             end
           )
  end

  test "valid_contact? rejects realized lookup errors" do
    refute ContactScopePolicy.valid_contact?(scope(), mission(), "contact-1",
             fetch_scheduled_contact: fn _organization_id, _mission_id, _contact_id ->
               {:error, :scheduled_contact_not_found}
             end,
             fetch_realized_contact: fn _organization_id, _mission_id, _contact_id ->
               {:error, :database_unavailable}
             end
           )
  end

  test "valid_contact? rejects non-binary contact ids" do
    refute ContactScopePolicy.valid_contact?(scope(), mission(), nil)
    refute ContactScopePolicy.valid_contact?(scope(), mission(), 123)
  end

  defp scope, do: %{organization_id: "org-1"}
  defp mission, do: %{mission_id: "mission-1"}
end
