defmodule Cadence.Control.ActorRefTest do
  @moduledoc "Drift sweep: requirement actors are user, service or system, never 'actor'."
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{User, UserRow}
  alias Cadence.Control.ActorRef

  test "a user by name, an unknown id as system" do
    user =
      User.new(%{user_id: "user-mira", email: "mira@example.test", display_name: "Mira K."})

    Repo.insert!(UserRow.changeset(user))

    assert ActorRef.resolve("org-x", user.user_id) == %{
             kind: "user",
             id: user.user_id,
             name: "Mira K."
           }

    assert ActorRef.resolve("org-x", "automation:nightly") == %{
             kind: "system",
             id: "automation:nightly",
             name: nil
           }

    assert %{kind: "system"} = ActorRef.resolve(nil, "automation:nightly")
  end
end
