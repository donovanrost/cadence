defmodule Cadence.Applications.OpsConsole.Actions.ProviderChangeDecisionsTest do
  use Cadence.DataCase, async: false
  alias Cadence.Applications.{ActionRequest, HostContext}
  alias Cadence.Applications.OpsConsole.Actions.ContactPlanning
  alias Cadence.Contacts.{ProviderChangeApprovals, ProviderReservationChanges}
  alias Cadence.ProviderChangeFixtures, as: Fixtures

  test "approval returns the persisted change receipt from the transaction result" do
    {c, change} = pending()
    assert {:ok, receipt} = execute(c, "approve-provider-change", input(c, change))
    assert receipt["providerReservationChangeId"] == change.provider_reservation_change_id
    assert receipt["providerRevision"] == 2
    assert receipt["proposalHash"] == change.proposal_hash
    assert receipt["lifecycleState"] == "approved"

    assert {:ok, approval} =
             ProviderChangeApprovals.fetch(
               c.organization_id,
               change.provider_reservation_change_id
             )

    assert approval.reason == "Reviewed operational impact"
  end

  test "rejection and acknowledgment return equally bound persisted receipts" do
    {c, change} = pending()

    assert {:ok, %{"lifecycleState" => "rejected"}} =
             execute(c, "reject-provider-change", input(c, change))

    c = Fixtures.setup_contact()

    assert {:ok, _} =
             Fixtures.advance(c, 2, %{
               "status" => "canceled",
               "extensions" => %{"provider_change" => %{"effective" => true}}
             })

    [change] =
      ProviderReservationChanges.list_for_reservation(
        c.organization_id,
        c.reservation.provider_reservation_id
      )

    assert {:ok, %{"lifecycleState" => "acknowledged"}} =
             execute(c, "acknowledge-provider-change", input(c, change))

    assert {:ok, %{lifecycle_state: :acknowledged}} =
             ProviderReservationChanges.fetch(
               c.organization_id,
               change.provider_reservation_change_id
             )
  end

  test "malformed, foreign, substituted, and stale reviews cannot persist a decision" do
    {c, change} = pending()
    good = input(c, change)

    invalid = [
      Map.delete(good, "change_evidence"),
      Map.put(good, "reason", " "),
      Map.put(good, "extra", true),
      put_in(good, ["change_evidence", "organization_id"], "foreign"),
      put_in(good, ["change_evidence", "mission_id"], "foreign"),
      put_in(good, ["change_evidence", "reservation_id"], "foreign"),
      put_in(good, ["change_evidence", "change_id"], "foreign"),
      put_in(good, ["change_evidence", "provider_revision"], 1),
      put_in(good, ["change_evidence", "contract_version"], 1.0),
      put_in(good, ["change_evidence", "proposal_hash"], String.duplicate("0", 64))
    ]

    for params <- invalid, do: assert({:error, _} = execute(c, "approve-provider-change", params))

    assert {:ok, %{lifecycle_state: :pending_approval}} =
             ProviderReservationChanges.fetch(
               c.organization_id,
               change.provider_reservation_change_id
             )

    assert {:error, :provider_change_approval_not_found} =
             ProviderChangeApprovals.fetch(
               c.organization_id,
               change.provider_reservation_change_id
             )

    assert {:ok, _} =
             Fixtures.advance(c, 3, %{
               "starts_at" => Fixtures.shift(c.baseline["starts_at"], 120),
               "ends_at" => Fixtures.shift(c.baseline["ends_at"], 120)
             })

    assert {:error, :stale_provider_change_evidence} = execute(c, "approve-provider-change", good)
  end

  defp pending do
    c = Fixtures.setup_contact()

    assert {:ok, _} =
             Fixtures.advance(c, 2, %{
               "starts_at" => Fixtures.shift(c.baseline["starts_at"], 60),
               "ends_at" => Fixtures.shift(c.baseline["ends_at"], 60)
             })

    [change] =
      ProviderReservationChanges.list_for_reservation(
        c.organization_id,
        c.reservation.provider_reservation_id
      )

    {c, change}
  end

  defp input(c, change),
    do: %{
      "provider_reservation_id" => c.reservation.provider_reservation_id,
      "reason" => "  Reviewed operational impact  ",
      "change_evidence" => %{
        "contract_version" => 1,
        "organization_id" => c.organization_id,
        "mission_id" => c.mission_id,
        "reservation_id" => c.reservation.provider_reservation_id,
        "change_id" => change.provider_reservation_change_id,
        "provider_revision" => change.provider_revision,
        "proposal_hash" => change.proposal_hash
      }
    }

  defp execute(c, action, params),
    do:
      ContactPlanning.execute(
        c.admin_scope,
        HostContext.mission(c.mission_id),
        "contact_detail",
        %ActionRequest{
          application_key: "ops_console",
          application_version: 1,
          action_id: action,
          params: params
        }
      )
end
