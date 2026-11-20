defmodule Cadence.Reads.PassContactFieldsTest do
  @moduledoc """
  U55/U56: which of cancel or end a pass offers, and how its contact ended (an operator, or
  Cadence because the reservation won't fly: the provider's words and code kept apart).
  """
  use Cadence.DataCase, async: true

  alias Cadence.Contacts.ContactAction
  alias Cadence.Reads.PassContactFields

  @now ~U[2026-11-14 13:00:00Z]

  defp fact(attrs),
    do:
      Map.merge(
        %{
          state: :scheduled,
          starts_at: ~U[2026-11-14 13:04:00Z],
          ends_at: ~U[2026-11-14 13:12:00Z],
          realized_contact_id: nil,
          live?: false,
          ending: nil
        },
        attrs
      )

  test "cancel before it's live, end while live, nothing after LOS or once ended" do
    assert PassContactFields.action(fact(%{}), @now) == "cancel"
    assert PassContactFields.action(fact(%{live?: true}), @now) == "end"
    assert PassContactFields.action(fact(%{}), ~U[2026-11-14 13:20:00Z]) == nil
    assert PassContactFields.action(fact(%{state: :canceled}), @now) == nil
    assert PassContactFields.action(nil, @now) == nil
  end

  test "Cadence's cancel names the provider's cause, its own words and its code" do
    action = %ContactAction{
      action_kind: :scheduled_contact_canceled,
      reason: "provider_failed",
      actor: %{"kind" => "system", "id" => "provider_reservation_reconciler"},
      metadata: %{
        "cause" => "provider_failed",
        "provider_reason" => nil,
        "provider_reason_code" => "delivery_descriptor_conflicts_with_transport"
      },
      occurred_at: @now
    }

    assert PassContactFields.ended(fact(%{ending: action}), %{}) == %{
             kind: "canceled",
             cause: "provider_failed",
             by: %{kind: "system", id: "provider_reservation_reconciler", name: nil},
             at: @now,
             reason: nil,
             reason_code: "delivery_descriptor_conflicts_with_transport"
           }
  end

  test "an early end by an operator reads as operator without stored cause metadata" do
    action = %ContactAction{
      action_kind: :realized_contact_ended_early,
      reason: "Wrong target",
      actor: %{"kind" => "user", "id" => "no-such-user"},
      metadata: %{ended_early?: true},
      occurred_at: @now
    }

    assert %{kind: "ended_early", cause: "operator", reason: "Wrong target", reason_code: nil} =
             PassContactFields.ended(fact(%{ending: action}), %{})
  end

  test "a cancel with no action record takes its lifecycle time; cause and by stay null" do
    assert PassContactFields.ended(fact(%{state: :canceled, canceled_at: @now}), %{}) == %{
             kind: "canceled",
             cause: nil,
             by: nil,
             at: @now,
             reason: nil,
             reason_code: nil
           }

    assert %{at: nil} = PassContactFields.ended(fact(%{state: :canceled}), %{})
  end

  test "an actor missing its kind or id is null, never half an actor" do
    for actor <- [%{"kind" => "system"}, %{"id" => "provider_reservation_reconciler"}, %{}] do
      action = %ContactAction{
        action_kind: :scheduled_contact_canceled,
        reason: "x",
        actor: actor,
        metadata: %{},
        occurred_at: @now
      }

      assert %{by: nil, at: @now} = PassContactFields.ended(fact(%{ending: action}), %{})
    end
  end
end
