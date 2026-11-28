defmodule Cadence.Accounts.AccessEventsTest do
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.AccessEvents
  alias Cadence.Repo

  test "a subscriber hears that a person's access changed" do
    :ok = AccessEvents.subscribe("user-1")
    assert :ok = AccessEvents.changed("user-1")
    assert_receive {:access_changed, "user-1"}
    assert :ok = AccessEvents.changed("user-2")
    refute_receive {:access_changed, "user-2"}, 50
  end

  test "announcing inside a transaction raises instead of silently dropping" do
    assert_raise ArgumentError, ~r/after the commit/, fn ->
      Repo.transaction(fn -> AccessEvents.changed("user-1") end)
    end
  end
end
