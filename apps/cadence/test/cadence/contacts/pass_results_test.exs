defmodule Cadence.Contacts.PassResultsTest do
  use Cadence.DataCase, async: false

  import Cadence.ConfigurationFixtures, only: [member_scope: 3]

  alias Cadence.Contacts.{PassResults, ProviderReservations}
  alias Cadence.ProviderChangeFixtures
  alias Cadence.Reads.PassReview

  defmodule ResultClient do
    @moduledoc false
    def fetch_contact_result(_context, _ref, _opts) do
      {:ok,
       %{
         "actual_acquisition_at" => "2026-07-20T12:00:05Z",
         "actual_loss_at" => "2026-07-20T12:10:00Z",
         "bytes_delivered" => 4_096,
         "frames_delivered" => 12,
         "observations" => %{"loss" => 0}
       }}
    end
  end

  defmodule SilentClient do
    @moduledoc false
  end

  setup do
    c = ProviderChangeFixtures.setup_contact(%{}, starts_at: ~U[2026-07-20 12:00:00.000000Z])
    %{c: c, alice: member_scope(c.organization_id, :member, "Alice")}
  end

  defp another(c, n) do
    attrs =
      c.reservation
      |> Map.from_struct()
      |> Map.merge(%{
        provider_reservation_id: "pass-#{n}",
        provider_contact_ref: "provider-contact-pass-#{n}",
        idempotency_key: "pass-key-#{n}",
        scheduled_contact_id: "pass-schedule-#{n}"
      })

    {:ok, reservation} = ProviderReservations.create_attempt(c.organization_id, attrs)
    reservation
  end

  @after_los [now: ~U[2026-07-20 13:00:00Z]]

  test "records realized, Cadence-canceled and unreported passes, and reviews the span",
       %{c: c} = ctx do
    realized = another(c, 1)

    # Never realized, so Cadence can't attribute received volume: nil, not 0.
    assert {:ok,
            %{
              outcome: "realized",
              provider_bytes: 4_096,
              received_bytes: nil,
              closed_at: %DateTime{}
            }} =
             PassResults.record(
               realized,
               @after_los ++
                 [client: ResultClient, received: fn _m, _id -> %{bytes: 3_000, frames: 12} end]
             )

    {:ok, canceling} =
      ProviderReservations.mark_canceling(
        c.organization_id,
        c.mission_id,
        c.reservation.provider_reservation_id
      )

    assert canceling.metadata["cancel_initiator"] == "cadence"

    assert {:ok, %{outcome: "canceled", owner: "us", disputable: false}} =
             PassResults.record(canceling, now: ~U[2026-07-20 11:00:00Z])

    assert {:ok, %{outcome: "pending_report", closed_at: nil}} =
             PassResults.record(another(c, 2), @after_los ++ [client: SilentClient])

    from = ~U[2026-07-20 00:00:00Z]
    to = ~U[2026-07-21 00:00:00Z]

    assert {:ok, summary} = PassReview.summary(ctx.alice, c.mission_id, from, to)

    assert %{planned: 3, realized: 1, canceled: 1, pending_count: 1, provisional: true} = summary
    assert summary.realized_ratio == 1.0
    assert summary.target == 0.98 and summary.threshold == 0.95

    assert {:ok, %{total: 3, rows: [_ | _], disputable: 0}} =
             PassReview.rows(ctx.alice, c.mission_id, from, to, %{limit: 2})

    assert {:ok, %{total: 1, rows: [%{outcome: "realized", provider_bytes: 4_096}]}} =
             PassReview.rows(ctx.alice, c.mission_id, from, to, %{outcome: ["realized"]})

    assert {:ok, %{days: [%{day: ~D[2026-07-20], planned: 3, realized: 1}], target: 0.98}} =
             PassReview.daily(ctx.alice, c.mission_id, from, to)
  end

  test "outsiders can't read pass review", %{c: c} do
    outsider =
      member_scope(c.organization_id, :member, "Eve") |> Map.put(:organization_membership, nil)

    assert {:error, :forbidden} =
             PassReview.summary(
               outsider,
               c.mission_id,
               ~U[2026-07-20 00:00:00Z],
               ~U[2026-07-21 00:00:00Z]
             )
  end
end
