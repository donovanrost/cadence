defmodule Cadence.Reads.OrganizationAudit.CommandLinesTest do
  @moduledoc "ux U59: the audit's commanding lines."
  use ExUnit.Case, async: true

  alias Cadence.Reads.OrganizationAudit.CommandLines, as: Lines

  @group %{commands: ["SET_MODE", "PING", "DUMP"], target_count: 12, own_values: 3}
  @label "SET_MODE and 2 more for 12 spacecraft"

  test "submitted, resent, and the per-target count" do
    assert Lines.submitted(%{payload: %{"second_go_required" => true}}, @group, nil) ==
             "Submitted #{@label} · needs a second GO · 3 spacecraft have their own values"

    resent = %{at: ~U[2026-11-15 13:02:10Z], title: "Safe mode recovery"}

    assert Lines.submitted(%{payload: %{}}, %{@group | own_values: 0}, resent) ==
             "Resent #{@label} (sent back at 13:02Z: “Safe mode recovery”)"
  end

  test "released into a booked pass, an unbooked contact, and a stop" do
    payload = %{"released_entry_ids" => ["a", "b"], "booked" => true}
    contact = %{code: "SVL", at: ~U[2026-11-15 14:05:00Z]}

    assert Lines.released(payload, @group, contact) ==
             "Released 2 uplinks of #{@label} into the SVL 14:05Z pass"

    stopped =
      %{payload | "booked" => false}
      |> Map.merge(%{"stopped" => %{}, "not_attempted_entry_ids" => ["c"]})

    assert Lines.released(stopped, @group, contact) ==
             "Released 2 uplinks of #{@label} into a contact that wasn't a booked pass (SVL 14:05Z)" <>
               " · then stopped, 1 uplink still queued"
  end

  test "HOLD acknowledged uses the check's words; Cadence's cancels say why" do
    assert Lines.hold_acknowledged(%{"key" => "contact"}, @group) ==
             "Acknowledged the Contact HOLD on #{@label}"

    assert Lines.group_canceled(3, "spacecraft_archived", ["EARENDIL-004"], @group) ==
             "Canceled 3 uplinks of #{@label}: EARENDIL-004 was archived"

    assert Lines.group_canceled(1, "catalog_changed: cs_1", [], @group) ==
             "Canceled 1 uplink of #{@label}: the catalog changed"

    assert Lines.group_canceled(4, "commanding_disabled: cs_2", ["A", "B", "C"], @group) ==
             "Canceled 4 uplinks of #{@label}: commanding was turned off for 3 of its spacecraft"

    assert Lines.member_canceled("SET_MODE", "EARENDIL-004", @group) ==
             "Canceled SET_MODE on EARENDIL-004 from #{@label}"

    assert Lines.request_canceled("SET_MODE", "EARENDIL-004", true, "commanding_disabled: cs_2") ==
             "Canceled SET_MODE on EARENDIL-004: commanding was turned off for it"

    assert Lines.group_canceled(2, "something_new", [], @group) ==
             "Canceled 2 uplinks of #{@label}."

    assert Lines.request_canceled("SET_MODE", "EARENDIL-004", true, "expired") ==
             "Canceled SET_MODE on EARENDIL-004: it expired before release"

    assert Lines.request_canceled("SET_MODE", nil, false, "Wrong target") == "Canceled SET_MODE"
  end
end
