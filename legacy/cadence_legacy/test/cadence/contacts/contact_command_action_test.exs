defmodule Cadence.Contacts.ContactCommandActionTest do
  use Cadence.DataCase, async: true

  alias Cadence.Contacts.ContactCommandAction

  test "changeset requires required fields and defaults" do
    changeset = ContactCommandAction.changeset(%ContactCommandAction{}, %{})
    refute changeset.valid?

    errors = errors_on(changeset)

    assert errors[:organization_id]
    assert errors[:mission_id]
    assert errors[:contact_id]
    assert errors[:command_ref]

    changeset =
      ContactCommandAction.changeset(%ContactCommandAction{}, %{
        organization_id: Ecto.UUID.generate(),
        mission_id: Ecto.UUID.generate(),
        contact_id: Ecto.UUID.generate(),
        command_ref: %{"command_name" => "PING"}
      })

    assert changeset.valid?
    assert Ecto.Changeset.get_field(changeset, :gate) == :uplink_ready
    assert Ecto.Changeset.get_field(changeset, :state) == :planned
    assert Ecto.Changeset.get_field(changeset, :order) == 0
  end
end
