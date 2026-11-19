defmodule Cadence.ContactPlanning.PlanUpdatesTest do
  @moduledoc "S10 contact_plans invalidation: after commit, and when a booking passes the window."
  use Cadence.DataCase, async: false

  alias Cadence.ContactPlanning.PlanUpdates
  alias Cadence.Platform.ScopedReadUpdates

  setup do
    :ok = ScopedReadUpdates.subscribe(:contact_plans_changed, "org-pu", "mission-pu")
    :ok
  end

  test "a successful write publishes; a failed one doesn't" do
    assert {:error, :nope} = PlanUpdates.published({:error, :nope}, "org-pu", "mission-pu")
    refute_receive {:contact_plans_changed, _, _}, 100

    assert {:ok, :plan} = PlanUpdates.published({:ok, :plan}, "org-pu", "mission-pu")
    assert_receive {:contact_plans_changed, "org-pu", "mission-pu"}
  end

  test "inside a transaction it publishes after a delay, not before the commit" do
    {:ok, :ok} = Repo.transaction(fn -> PlanUpdates.changed("org-pu", "mission-pu") end)
    refute_receive {:contact_plans_changed, _, _}, 300
    assert_receive {:contact_plans_changed, "org-pu", "mission-pu"}, 2_000
  end

  test "a booking placed longer ago than the window publishes right away" do
    long_ago = DateTime.add(DateTime.utc_now(), -3_600)
    :ok = PlanUpdates.when_unconfirmed("org-pu", "mission-pu", long_ago)
    assert_receive {:contact_plans_changed, "org-pu", "mission-pu"}, 1_000
  end
end
