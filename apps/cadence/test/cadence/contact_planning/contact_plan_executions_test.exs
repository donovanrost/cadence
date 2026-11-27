defmodule Cadence.ContactPlanning.ContactPlanExecutionsTest do
  use Cadence.DataCase, async: false

  import Ecto.Query

  alias Cadence.Management.Transports

  alias Cadence.Accounts.{OrganizationMembership, User, UserRow}
  alias Cadence.Auth.Scope
  alias Cadence.Comms.Transport
  alias Cadence.ConfigurationFixtures

  alias Cadence.ContactPlanning.{
    ContactPlanExecutions,
    ContactPlans,
    ContactRequirements,
    FleetRunLock,
    Planner
  }

  alias Cadence.Control.Contacts, as: ControlContacts
  alias Cadence.Control.Contacts.Store.ContactPlanExecutionItemRow
  alias Cadence.Control.PlanConfirmation
  alias Cadence.Control.Scheduling
  alias Cadence.Management.Contacts, as: ManagementContacts
  alias Cadence.Management.Contacts.Store.ContactPlanRow
  alias Cadence.Reads.PlanCoverageAttention

  alias Cadence.Contacts.{PathTemplate, ProviderBooking, ProviderReservations}
  alias Cadence.GroundNetworks
  alias Cadence.GroundNetworks.{MissionProvider, ProviderError}
  alias Cadence.Spacecraft
  alias Cadence.TestSupport.FakeProviderClient

  @now ~U[2026-07-16 20:00:00.000000Z]

  setup do
    suffix = System.unique_integer([:positive])
    organization_id = "org-contact-plan-execution-#{suffix}"
    mission_id = "mission-contact-plan-execution-#{suffix}"
    spacecraft_id = "spacecraft-contact-plan-execution-#{suffix}"

    %{organization: organization} = persist_mission_scope(organization_id, mission_id)

    assert {:ok, _spacecraft} =
             Cadence.SpacecraftStore.persist_spacecraft(
               organization_id,
               Spacecraft.new(%{
                 spacecraft_id: spacecraft_id,
                 mission_id: mission_id,
                 display_name: "Asteria"
               })
             )

    provider = persist_provider!(organization_id, mission_id, suffix)

    assert {:ok, transport} =
             Transports.persist_transport(
               organization_id,
               Transport.new(%{
                 transport_id: "provider-transport-#{suffix}",
                 mission_id: mission_id,
                 display_name: "Simulator telemetry ingress",
                 origin: :provider_managed,
                 mission_provider_id: provider.provider_id,
                 mission_provider_version: provider.version,
                 service_profile_ref: %{
                   "id" => "service-realtime-ttc-downlink",
                   "version" => 3
                 },
                 delivery_profile_ref: %{
                   "id" => "delivery-cadence-primary",
                   "version" => 7
                 }
               })
             )

    assert {:ok, runtime_profile} =
             Cadence.Contacts.fetch_provider_profile(
               organization_id,
               mission_id,
               transport.materialized_provider_profile_id
             )

    assert {:ok, path_template} =
             Cadence.Contacts.persist_path_template(
               organization_id,
               PathTemplate.new(%{
                 path_template_id: "simulator-downlink-#{suffix}",
                 mission_id: mission_id,
                 path_id: "simulator-downlink-path-#{suffix}",
                 direction: :downlink,
                 selection_role: :selected,
                 source_endpoint_ref: "source-endpoint-#{suffix}",
                 provider_profile_refs: [
                   %{
                     "provider_profile_id" => runtime_profile.provider_profile_id,
                     "version" => runtime_profile.version
                   }
                 ]
               })
             )

    member_scope = scope(organization, :member, suffix)
    admin_scope = scope(organization, :organization_admin, suffix)

    route =
      route(%{
        suffix: suffix,
        spacecraft_id: spacecraft_id,
        provider: provider,
        transport: transport,
        runtime_profile: runtime_profile,
        path_template: path_template
      })

    assert {:ok, requirement, requirement_version} =
             ContactRequirements.create(
               member_scope,
               mission_id,
               requirement_attrs(spacecraft_id),
               now: @now
             )

    assert {:ok, planning} =
             Planner.run(
               member_scope,
               mission_id,
               requirement.contact_requirement_id,
               requirement_version.version,
               now: @now,
               list_routes: fn _, _, _ -> {:ok, %{routes: [route], findings: []}} end,
               search_opportunities: fn _, _, _, _, _ ->
                 {:ok,
                  %{
                    opportunities: [
                      opportunity("primary", 3_600, 4_500),
                      opportunity("backup", 7_200, 8_100)
                    ]
                  }}
               end
             )

    assert {:ok, plan, plan_version} =
             ContactPlans.create(member_scope, mission_id, %{
               planning_run_ids: [planning.run.contact_planning_run_id],
               selected_snapshot_ids:
                 Enum.map(planning.snapshots, & &1.contact_opportunity_snapshot_id),
               rationale: "Reserve both passes for recorder relief"
             })

    assert {:ok, _pending} =
             ContactPlans.submit(
               member_scope,
               mission_id,
               plan.contact_plan_id,
               1,
               "Ready for review"
             )

    resolve_route = fn _, _, _, _ -> {:ok, route} end

    assert {:ok, approved_handoff} =
             ManagementContacts.approve_plan(
               admin_scope,
               mission_id,
               plan.contact_plan_id,
               1,
               plan_version.content_sha256,
               "Approved both provider commitments",
               now: DateTime.add(@now, 1, :second),
               resolve_route: resolve_route
             )

    assert [] ==
             ContactPlanExecutions.list(
               organization_id,
               mission_id,
               plan.contact_plan_id,
               plan_version.version
             )

    assert :ok = ControlContacts.accept_approved_plan(approved_handoff)
    assert :ok = ControlContacts.accept_approved_plan(approved_handoff)

    assert {:ok, approved_plan, _version} =
             ManagementContacts.fetch_plan(organization_id, mission_id, plan.contact_plan_id)

    %{
      organization_id: organization_id,
      organization: organization,
      suffix: suffix,
      mission_id: mission_id,
      member_scope: member_scope,
      plan: approved_plan,
      route: route,
      resolve_route: resolve_route
    }
  end

  test "Control accepts an approved handoff and links exact Plan evidence to reservations",
       context do
    pending_items =
      ContactPlanExecutions.list(
        context.organization_id,
        context.mission_id,
        context.plan.contact_plan_id,
        1
      )

    assert length(pending_items) == 2
    assert Enum.all?(pending_items, &(&1.lifecycle_state == :pending))
    assert Enum.uniq_by(pending_items, & &1.idempotency_key) == pending_items

    test_pid = self()
    reserve = successful_reserver(test_pid)

    assert {:ok, result} =
             ContactPlanExecutions.execute(
               context.member_scope,
               context.mission_id,
               context.plan.contact_plan_id,
               now: DateTime.add(@now, 2, :second),
               resolve_route: context.resolve_route,
               reserve: reserve
             )

    assert result.plan.lifecycle_state == :reserved
    assert Enum.all?(result.items, &(&1.lifecycle_state == :reserved))
    assert Enum.all?(result.items, &is_binary(&1.provider_reservation_id))
    assert_received {:provider_mutation, _first}
    assert_received {:provider_mutation, _second}

    assert %{execution: execution} =
             PlanConfirmation.detail(
               context.organization_id,
               context.mission_id,
               context.plan.contact_plan_id
             )

    assert execution == %{
             requested: 2,
             sent: 2,
             never_sent: 0,
             confirmed: 2,
             uncertain: 0,
             rejected: 0,
             failed: 0,
             provider_names: ["Ground Network Simulator"]
           }

    Enum.each(result.items, fn item ->
      assert {:ok, reservation} =
               ProviderReservations.fetch(
                 context.organization_id,
                 context.mission_id,
                 item.provider_reservation_id
               )

      assert reservation.contact_plan_id == context.plan.contact_plan_id
      assert reservation.contact_plan_version == 1

      assert reservation.contact_opportunity_snapshot_id ==
               item.contact_opportunity_snapshot_id

      assert reservation.idempotency_key == item.idempotency_key
      assert is_binary(reservation.contact_requirement_id)
      assert reservation.contact_requirement_version == 1
    end)

    assert {:ok, replay} =
             ContactPlanExecutions.execute(
               context.member_scope,
               context.mission_id,
               context.plan.contact_plan_id,
               now: DateTime.add(@now, 3, :second),
               resolve_route: context.resolve_route,
               reserve: reserve
             )

    assert replay.plan.lifecycle_state == :reserved
    refute_received {:provider_mutation, _opportunity_ref}
  end

  test "a booking the provider cancels later is lost and the plan becomes repairable (qa #22)",
       context do
    {:ok, %{plan: %{lifecycle_state: :reserved}, items: [lost | _]}} =
      ContactPlanExecutions.execute(
        context.member_scope,
        context.mission_id,
        context.plan.contact_plan_id,
        now: DateTime.add(@now, 2, :second),
        resolve_route: context.resolve_route,
        reserve: successful_reserver(self())
      )

    {:ok, reservation} =
      ProviderReservations.fetch(
        context.organization_id,
        context.mission_id,
        lost.provider_reservation_id
      )

    canceled =
      reservation.provider_confirmed_snapshot_document
      |> Map.merge(%{
        "id" => reservation.provider_contact_ref,
        "provider_revision" => reservation.provider_revision + 1,
        "status" => "canceled",
        "provider_status" => "canceled",
        "status_reason" => "station_unavailable"
      })

    assert {:ok, %{lifecycle_state: :canceled}} =
             ProviderReservations.apply_provider_status(
               context.organization_id,
               context.mission_id,
               reservation.provider_reservation_id,
               canceled
             )

    items =
      ContactPlanExecutions.list(
        context.organization_id,
        context.mission_id,
        context.plan.contact_plan_id,
        1
      )

    assert %{lifecycle_state: :failed, last_error_document: %{"code" => "booking_lost"}} =
             Enum.find(
               items,
               &(&1.contact_plan_execution_item_id == lost.contact_plan_execution_item_id)
             )

    assert {:ok, %{lifecycle_state: :partially_reserved}, _version} =
             ContactPlans.fetch(
               context.organization_id,
               context.mission_id,
               context.plan.contact_plan_id
             )
  end

  test "bookings the provider confirms after execution ends settle the plan (K2 Apply)",
       context do
    pending = fn organization_id, mission_id, provider_id, attrs, _opts ->
      reserve_with_response(
        organization_id,
        mission_id,
        provider_id,
        attrs,
        {:ok, provider_response(attrs, "pending")}
      )
    end

    assert {:ok, %{plan: %{lifecycle_state: :executing}, items: items}} =
             ContactPlanExecutions.execute(
               context.member_scope,
               context.mission_id,
               context.plan.contact_plan_id,
               now: DateTime.add(@now, 2, :second),
               resolve_route: context.resolve_route,
               reserve: pending
             )

    assert Enum.all?(items, &(&1.lifecycle_state == :uncertain))

    # Re-reading uncertain items (Execute resumes, end-of-execution re-check) doesn't rewrite
    # them, so the confirmation window (#52) still runs from when they went uncertain.
    assert {:ok, %{items: reread}} =
             ContactPlanExecutions.execute(
               context.member_scope,
               context.mission_id,
               context.plan.contact_plan_id,
               now: DateTime.add(@now, 60, :second),
               resolve_route: context.resolve_route,
               reserve: pending
             )

    assert Enum.map(reread, & &1.updated_at) == Enum.map(items, & &1.updated_at)

    # U30: within the window nothing is unconfirmed; past it, plan detail names the passes.
    unconfirmed =
      &PlanConfirmation.unconfirmed(
        context.organization_id,
        context.mission_id,
        context.plan.contact_plan_id,
        now: DateTime.add(@now, &1, :minute),
        window_ms: :timer.minutes(10)
      )

    assert unconfirmed.(1) == nil
    assert %{window_ms: 600_000, booked: 0, passes: passes} = unconfirmed.(11)

    assert Enum.sort(Enum.map(passes, & &1.snapshot_id)) ==
             Enum.sort(Enum.map(items, & &1.contact_opportunity_snapshot_id))

    assert Enum.all?(
             passes,
             &match?(
               %{provider: %{id: id, name: "Ground Network Simulator"}, sent_at: %DateTime{}}
               when is_binary(id),
               &1
             )
           )

    for item <- items do
      {:ok, reservation} =
        ProviderReservations.fetch(
          context.organization_id,
          context.mission_id,
          item.provider_reservation_id
        )

      confirmed =
        Map.merge(reservation.provider_confirmed_snapshot_document, %{
          "id" => reservation.provider_contact_ref,
          "provider_revision" => reservation.provider_revision + 1,
          "status" => "confirmed",
          "provider_status" => "confirmed"
        })

      assert {:ok, %{lifecycle_state: :confirmed}} =
               ProviderReservations.apply_provider_status(
                 context.organization_id,
                 context.mission_id,
                 reservation.provider_reservation_id,
                 confirmed
               )
    end

    assert ContactPlanExecutions.list(
             context.organization_id,
             context.mission_id,
             context.plan.contact_plan_id,
             1
           )
           |> Enum.all?(&(&1.lifecycle_state == :reserved))

    assert {:ok, %{lifecycle_state: :reserved}, _version} =
             ContactPlans.fetch(
               context.organization_id,
               context.mission_id,
               context.plan.contact_plan_id
             )
  end

  test "mixed provider outcomes preserve committed capacity and project partial success",
       context do
    reserve = fn organization_id, mission_id, provider_id, attrs, _opts ->
      if attrs["opportunity_ref"] == "opportunity-primary" do
        reserve_with_response(
          organization_id,
          mission_id,
          provider_id,
          attrs,
          {:ok, provider_response(attrs, "confirmed")}
        )
      else
        reserve_with_response(
          organization_id,
          mission_id,
          provider_id,
          attrs,
          {:error,
           ProviderError.from_response(409, %{
             "error" => %{"code" => "no_capacity", "detail" => "antenna unavailable"}
           })}
        )
      end
    end

    assert {:ok, result} =
             ContactPlanExecutions.execute(
               context.member_scope,
               context.mission_id,
               context.plan.contact_plan_id,
               now: DateTime.add(@now, 2, :second),
               resolve_route: context.resolve_route,
               reserve: reserve
             )

    assert result.plan.lifecycle_state == :partially_reserved
    assert Enum.sort(Enum.map(result.items, & &1.lifecycle_state)) == [:rejected, :reserved]

    assert length(
             Cadence.Contacts.list_scheduled_contacts(context.organization_id, context.mission_id)
           ) ==
             1
  end

  test "ambiguous writes remain uncertain and are not blindly retried", context do
    test_pid = self()

    reserve = fn organization_id, mission_id, provider_id, attrs, _opts ->
      send(test_pid, {:provider_mutation, attrs["opportunity_ref"]})

      reserve_with_response(
        organization_id,
        mission_id,
        provider_id,
        attrs,
        {:error, ProviderError.ambiguous(%{"reason" => "connection_closed"})}
      )
    end

    assert {:ok, first} =
             ContactPlanExecutions.execute(
               context.member_scope,
               context.mission_id,
               context.plan.contact_plan_id,
               now: DateTime.add(@now, 2, :second),
               resolve_route: context.resolve_route,
               reserve: reserve
             )

    assert first.plan.lifecycle_state == :executing
    assert Enum.all?(first.items, &(&1.lifecycle_state == :uncertain))
    assert_received {:provider_mutation, _first}
    assert_received {:provider_mutation, _second}

    assert {:ok, second} =
             ContactPlanExecutions.execute(
               context.member_scope,
               context.mission_id,
               context.plan.contact_plan_id,
               now: DateTime.add(@now, 3, :second),
               resolve_route: context.resolve_route,
               reserve: reserve
             )

    assert Enum.all?(second.items, &(&1.lifecycle_state == :uncertain))
    refute_received {:provider_mutation, _opportunity_ref}
  end

  test "an unattended plan awaiting its provider reads executing, then unconfirmed past the window (DECISIONS #52)",
       context do
    assert {:ok, %{plan: %{lifecycle_state: :executing}, items: [_, _]}} =
             execute(context, ambiguous_reserver(self()))

    state = fn opts ->
      Scheduling.plan_state(
        context.organization_id,
        context.mission_id,
        context.plan.contact_plan_id,
        :executing,
        opts
      )
    end

    # Items were placed at the execution's `now` (@now + 2 s); the window counts from there.
    now = DateTime.add(@now, 3, :second)
    assert state.(now: now) == :executing
    assert state.(now: DateTime.add(now, 11, :minute)) == :unconfirmed

    assert state.(now: DateTime.add(now, 2, :second), confirmation_window_ms: 1_000) ==
             :unconfirmed
  end

  test "Execute on an interrupted plan resumes unplaced items and never re-sends uncertain ones (DECISIONS #52)",
       context do
    assert {:ok, %{items: items}} = execute(context, ambiguous_reserver(self()))
    assert_received {:provider_mutation, _first}
    assert_received {:provider_mutation, _second}

    # The session died before placing one pass: it never left `pending`.
    [_uncertain, unplaced] = items

    ContactPlanExecutionItemRow
    |> where([i], i.contact_plan_execution_item_id == ^unplaced.contact_plan_execution_item_id)
    |> Repo.update_all(set: [lifecycle_state: "pending", provider_reservation_id: nil])

    Repo.query!("DELETE FROM provider_reservations WHERE provider_reservation_id = $1", [
      unplaced.provider_reservation_id
    ])

    assert Scheduling.plan_state(
             context.organization_id,
             context.mission_id,
             context.plan.contact_plan_id,
             :executing
           ) == :interrupted

    assert {:ok, %{items: resumed}} = execute(context, ambiguous_reserver(self()))

    # Exactly one provider write: the unplaced pass. The uncertain one is only re-read.
    assert_received {:provider_mutation, _unplaced}
    refute_received {:provider_mutation, _uncertain}
    assert Enum.all?(resumed, &(&1.lifecycle_state == :uncertain))
  end

  describe "api's booking findings (2026-11-13)" do
    test "a provider that rejects by status keeps its reason on the item", context do
      reserve = fn organization_id, mission_id, provider_id, attrs, _opts ->
        response =
          attrs
          |> provider_response("rejected")
          |> Map.put("status_reason", %{"category" => "no_capacity", "detail" => "antenna busy"})

        reserve_with_response(organization_id, mission_id, provider_id, attrs, {:ok, response})
      end

      assert {:ok, result} = execute(context, reserve)

      for item <- result.items do
        assert item.lifecycle_state == :rejected

        assert %{"reason" => %{"category" => "no_capacity", "detail" => "antenna busy"}} =
                 item.last_error_document
      end
    end

    test "an item another run moved on is skipped, never marked failed", context do
      test_pid = self()

      reserve = fn organization_id, mission_id, provider_id, attrs, _opts ->
        send(test_pid, {:provider_mutation, attrs["opportunity_ref"]})

        # As if a concurrent run had already booked every other pending item.
        ContactPlanExecutionItemRow
        |> Ecto.Query.where(
          [row],
          row.contact_plan_id == ^context.plan.contact_plan_id and
            row.lifecycle_state == "pending"
        )
        |> Cadence.Repo.update_all(set: [lifecycle_state: "reserved"])

        reserve_with_response(
          organization_id,
          mission_id,
          provider_id,
          attrs,
          {:ok, provider_response(attrs, "confirmed")}
        )
      end

      assert {:ok, result} = execute(context, reserve)

      assert_received {:provider_mutation, _first}
      refute_received {:provider_mutation, _second}
      assert Enum.all?(result.items, &(&1.lifecycle_state == :reserved))
    end

    test "a provider configuration failure leaves the item placed, with its category", context do
      reserve = fn organization_id, mission_id, provider_id, attrs, _opts ->
        {:error, {:provider_reservation_not_confirmed, reservation}} =
          reserve_with_response(
            organization_id,
            mission_id,
            provider_id,
            attrs,
            {:error, ProviderError.ambiguous(%{"reason" => "connection_closed"})}
          )

        {:error,
         {:provider_configuration_failure, reservation,
          %{"reason" => %{"category" => "credentials_rejected", "detail" => "bad key"}}}}
      end

      assert {:ok, result} = execute(context, reserve)

      for item <- result.items do
        assert item.lifecycle_state == :failed
        assert is_binary(item.provider_reservation_id)

        assert item.last_error_document == %{
                 "code" => "provider_configuration_failure",
                 "reason" => %{"category" => "credentials_rejected", "detail" => "bad key"}
               }
      end

      assert %{never_sent: 0} =
               PlanConfirmation.execution(
                 ContactPlanExecutions.list(
                   context.organization_id,
                   context.mission_id,
                   context.plan.contact_plan_id,
                   context.plan.approved_version || 1
                 )
               )
    end

    test "every execute path holds the plan's execution lock", context do
      test_pid = self()

      key =
        ContactPlanExecutions.execution_key(
          context.organization_id,
          context.mission_id,
          context.plan.contact_plan_id
        )

      holder =
        spawn(fn ->
          FleetRunLock.with_key(key, fn ->
            send(test_pid, :held)

            receive do
              :release -> :ok
            end
          end)
        end)

      assert_receive :held, 5_000

      # Released in an after: a failed assert can't leave the holder blocked with its session open.
      try do
        assert {:error, :fleet_planning_run_busy} =
                 ControlContacts.execute_approved_plan(
                   context.member_scope,
                   context.mission_id,
                   context.plan.contact_plan_id,
                   reserve: successful_reserver(test_pid),
                   resolve_route: context.resolve_route,
                   now: DateTime.add(@now, 2, :second)
                 )

        refute_received {:provider_mutation, _any}
      after
        release(holder, key)
      end
    end
  end

  describe "#268: who started booking" do
    test "the first claim records the one who started it, not the approver; a second run keeps it",
         context do
      second = scope(context.organization, :member, "second-#{context.suffix}")
      reserve = successful_reserver(self())

      assert {:ok, _first} = execute(context, reserve)
      assert_received {:provider_mutation, _ref}
      flush_mutations()

      # A second Book, by someone else, after the first claimed it: it books nothing more and
      # leaves the starter as it was (ca-security).
      assert {:ok, _second} =
               ContactPlanExecutions.execute(
                 second,
                 context.mission_id,
                 context.plan.contact_plan_id,
                 now: DateTime.add(@now, 3, :second),
                 resolve_route: context.resolve_route,
                 reserve: reserve
               )

      refute_receive {:provider_mutation, _ref}, 100

      assert {:ok, plan, _version} =
               ManagementContacts.fetch_plan(
                 context.organization_id,
                 context.mission_id,
                 context.plan.contact_plan_id
               )

      assert plan.lifecycle_changed_by == context.member_scope.user.user_id
      refute plan.lifecycle_changed_by == plan.approved_by
    end

    test "a stopped run's resume (failed, partially_reserved) records whoever resumed it",
         context do
      reserve = successful_reserver(self())
      assert {:ok, _first} = execute(context, reserve)
      flush_mutations()

      for {state, n} <- [{"failed", 1}, {"partially_reserved", 2}] do
        resumer = scope(context.organization, :member, "resume-#{n}-#{context.suffix}")
        put_plan_state(context, state)

        assert {:ok, _resumed} =
                 ContactPlanExecutions.execute(
                   resumer,
                   context.mission_id,
                   context.plan.contact_plan_id,
                   now: DateTime.add(@now, 3 + n, :second),
                   resolve_route: context.resolve_route,
                   reserve: reserve
                 )

        assert {:ok, plan, _version} =
                 ManagementContacts.fetch_plan(
                   context.organization_id,
                   context.mission_id,
                   context.plan.contact_plan_id
                 )

        assert plan.lifecycle_changed_by == resumer.user.user_id, state
      end
    end
  end

  # The setup's plan: approved at @now + 1 s and accepted (items pending), never executed. Its
  # passes are on 07-16; the requirement's window opens 21:00Z that day.
  describe "U61 plan_coverage: a day whose booking hasn't started, or stopped (lead 11-16)" do
    test "approve-plan without execute-plan: covered within the 2-minute grace, open after it",
         context do
      assert coverage(context, DateTime.add(@now, 60, :second)) == nil

      assert %{
               plan: %{
                 state: "approved",
                 revision: 1,
                 approved_at: approved_at,
                 # #268: what Now's 'Book N passes' shows (every accepted pass, none placed yet).
                 booking: %{bookable: bookable, total: bookable, reserved: 0}
               },
               first_window_at: first,
               severity: "caution",
               p1: true
             } = coverage(context, DateTime.add(@now, 4, :minute))

      assert approved_at == context.plan.approved_at
      assert first == DateTime.add(@now, 3_600, :second)
      assert bookable > 0
    end

    # #468 (B): the approvers are the organization's active admins, named by display name only; an
    # admin without one reads name nil (keeping their id), never their email.
    test "approvers: active admins by display name, a nameless one with name nil, never email",
         context do
      org = context.organization_id
      named = ConfigurationFixtures.member_scope(org, :organization_admin, "Ana")
      nameless = ConfigurationFixtures.member_scope(org, :organization_admin, "x")
      nameless_id = nameless.user.user_id

      Repo.update_all(from(u in UserRow, where: u.user_id == ^nameless_id),
        set: [display_name: ""]
      )

      member = ConfigurationFixtures.member_scope(org, :member, "Mo")

      %{approvers: approvers} = coverage(context, DateTime.add(@now, 4, :minute))

      assert %{id: named.user.user_id, name: "Ana"} in approvers
      assert %{id: nameless_id, name: nil} in approvers
      refute Enum.any?(approvers, &(&1.id == member.user.user_id))
      refute inspect(approvers) =~ "@"
    end

    test "booking under way (its lock held) is covered; lock free with a pass never placed reopens",
         context do
      assert {:ok, %{items: [_uncertain, unplaced]}} =
               execute(context, ambiguous_reserver(self()))

      put_pending(unplaced)
      now = DateTime.add(@now, 4, :minute)

      with_execution_lock(context, fn -> assert coverage(context, now) == nil end)

      assert %{
               plan: %{
                 state: "interrupted",
                 approved_at: %DateTime{},
                 booking: %{reserved: 0, total: 2, last_progress_at: %DateTime{}}
               }
             } = coverage(context, now)
    end

    test "a run that stopped after booking some passes reads interrupted, not partially reserved",
         context do
      assert {:ok, %{items: [_booked, other]}} = execute(context, successful_reserver(self()))
      put_pending(other)
      put_plan_state(context, "partially_reserved")
      now = DateTime.add(@now, 4, :minute)

      assert plan_state(context, :partially_reserved) == :interrupted

      assert %{plan: %{state: "interrupted", booking: %{reserved: 1, total: 2}}} =
               coverage(context, now)

      # Every item finished (one rejected): it stays partially reserved, and the day is covered.
      put_item_state(other, "rejected")
      assert plan_state(context, :partially_reserved) == :partially_reserved
      assert coverage(context, now) == nil
    end

    test "resolutions: booking started after the grace; a day that ends unbooked", context do
      start = DateTime.add(@now, 5, :minute)
      assert {:ok, _result} = execute(context, successful_reserver(self()), start)

      assert [%{action: "booking_started", from_state: "approved", resolved_at: ^start}] =
               resolved(
                 context,
                 DateTime.add(start, -30, :second),
                 DateTime.add(start, 10, :second)
               )

      put_plan_state(context, "approved")
      day_end = ~U[2026-07-17 00:00:00.000000Z]

      assert [%{action: "day_ended", resolved_at: ^day_end, plan_revision: 1}] =
               resolved(
                 context,
                 DateTime.add(day_end, -30, :second),
                 DateTime.add(day_end, 10, :second)
               )
    end
  end

  defp coverage(context, now) do
    context.organization_id
    |> PlanCoverageAttention.items(context.mission_id, now: now)
    |> Enum.find(&(&1.id == "2026-07-16"))
  end

  defp resolved(context, since, now) do
    context.organization_id
    |> PlanCoverageAttention.resolved_since(context.mission_id, since, now: now)
    |> Enum.filter(&(&1.day == "2026-07-16"))
  end

  defp plan_state(context, state),
    do:
      Scheduling.plan_state(
        context.organization_id,
        context.mission_id,
        context.plan.contact_plan_id,
        state
      )

  defp flush_mutations do
    receive do
      {:provider_mutation, _ref} -> flush_mutations()
    after
      0 -> :ok
    end
  end

  defp put_pending(item) do
    put_item_state(item, "pending", provider_reservation_id: nil)

    Repo.query!("DELETE FROM provider_reservations WHERE provider_reservation_id = $1", [
      item.provider_reservation_id
    ])
  end

  defp put_item_state(item, state, extra \\ []) do
    ContactPlanExecutionItemRow
    |> where([i], i.contact_plan_execution_item_id == ^item.contact_plan_execution_item_id)
    |> Repo.update_all(set: [lifecycle_state: state] ++ extra)
  end

  defp put_plan_state(context, state) do
    ContactPlanRow
    |> where([p], p.contact_plan_id == ^context.plan.contact_plan_id)
    |> Repo.update_all(set: [lifecycle_state: state])
  end

  defp with_execution_lock(context, fun) do
    test_pid = self()

    key =
      ContactPlanExecutions.execution_key(
        context.organization_id,
        context.mission_id,
        context.plan.contact_plan_id
      )

    holder =
      spawn(fn ->
        FleetRunLock.with_key(key, fn ->
          send(test_pid, :held)

          receive do
            :release -> :ok
          end
        end)
      end)

    assert_receive :held, 5_000

    try do
      fun.()
    after
      release(holder, key)
    end
  end

  # The execution lock is a PostgreSQL session lock (FleetRunLock): the holder lets go by ending
  # its session, and the server frees the lock only once that session is gone, AFTER the holder
  # has moved on. So wait for the holder to exit and the server to stop reporting the lock held;
  # otherwise the next read can still see it held (#182: coverage read nil, "covered", at :726).
  defp release(holder, key) do
    ref = Process.monitor(holder)
    send(holder, :release)
    assert_receive {:DOWN, ^ref, :process, ^holder, _reason}, 5_000
    wait_until_free(key, 250)
  end

  defp wait_until_free(key, 0),
    do: flunk("the plan's execution lock is still held after its holder exited: #{inspect(key)}")

  # key_held?/1 answers false if its query errors, so this can pass without seeing the lock free;
  # the test's next read then fails loudly, which is enough here (devops' review).
  defp wait_until_free(key, tries) do
    if FleetRunLock.key_held?(key) do
      Process.sleep(20)
      wait_until_free(key, tries - 1)
    end
  end

  defp execute(context, reserve, now \\ DateTime.add(@now, 2, :second)) do
    ContactPlanExecutions.execute(
      context.member_scope,
      context.mission_id,
      context.plan.contact_plan_id,
      now: now,
      resolve_route: context.resolve_route,
      reserve: reserve
    )
  end

  defp ambiguous_reserver(test_pid) do
    fn organization_id, mission_id, provider_id, attrs, _opts ->
      send(test_pid, {:provider_mutation, attrs["opportunity_ref"]})

      reserve_with_response(
        organization_id,
        mission_id,
        provider_id,
        attrs,
        {:error, ProviderError.ambiguous(%{"reason" => "connection_closed"})}
      )
    end
  end

  defp successful_reserver(test_pid) do
    fn organization_id, mission_id, provider_id, attrs, _opts ->
      send(test_pid, {:provider_mutation, attrs["opportunity_ref"]})

      reserve_with_response(
        organization_id,
        mission_id,
        provider_id,
        attrs,
        {:ok, provider_response(attrs, "confirmed")}
      )
    end
  end

  defp reserve_with_response(organization_id, mission_id, provider_id, attrs, response) do
    ProviderBooking.reserve(
      organization_id,
      mission_id,
      provider_id,
      attrs,
      client: FakeProviderClient,
      reserve_response: response
    )
  end

  defp provider_response(attrs, status) do
    %{
      "id" => "external-#{attrs["opportunity_ref"]}",
      "provider_contact_ref" => "provider-contact-#{attrs["opportunity_ref"]}",
      "status" => status,
      "provider_status" => status,
      "pass_phase" => "scheduled",
      "delivery_state" => "ready",
      "client_reference" => attrs["idempotency_key"],
      "opportunity_ref" => attrs["opportunity_ref"],
      "spacecraft_ref" => attrs["provider_spacecraft_ref"],
      "service_profile_ref" => attrs["service_profile_ref"]["id"],
      "delivery_profile_ref" => attrs["delivery_profile_ref"]["id"],
      "delivery_descriptor" => delivery_descriptor(attrs),
      "starts_at" => iso(attrs["starts_at"]),
      "ends_at" => iso(attrs["ends_at"]),
      "provider_evidence" => %{"ground_station_ref" => attrs["ground_station_ref"]}
    }
  end

  defp delivery_descriptor(attrs) do
    %{
      "status" => "ready",
      "direction" => "downlink",
      "delivery_kind" => "realtime_stream",
      "mode" => "provider_connects",
      "source_addresses" => ["127.0.0.1/32", "::1/128"],
      "protocol" => "tcp",
      "endpoint_ref" => attrs["delivery_profile_ref"]["id"],
      "framing" => %{"family" => "ccsds_tm", "mode" => "fixed_size", "frame_bytes" => 1115},
      "allowed_source_refs" => [attrs["provider_spacecraft_ref"]],
      "activation_window" => %{
        "starts_at" => iso(attrs["starts_at"]),
        "ends_at" => iso(attrs["ends_at"])
      },
      "credential_ref" => nil,
      "diagnostics" => %{}
    }
  end

  defp route(context) do
    %{
      route_key: "route-#{context.suffix}",
      spacecraft_id: context.spacecraft_id,
      provider_spacecraft_ref: "SC-#{context.suffix}",
      source_endpoint_id: "source-endpoint-#{context.suffix}",
      routing_rule_id: "routing-#{context.suffix}",
      link_assignment_id: "link-#{context.suffix}",
      path_template_id: context.path_template.path_template_id,
      path_template_version: context.path_template.version,
      transport_id: context.transport.transport_id,
      transport_version: context.transport.version,
      transport_display_name: context.transport.display_name,
      provider_id: context.provider.provider_id,
      provider_version: context.provider.version,
      provider_account_id: context.provider.provider_account_id,
      provider_account_version: context.provider.provider_account_version,
      provider_account_grant_id: context.provider.provider_account_grant_id,
      provider_account_grant_version: context.provider.provider_account_grant_version,
      provider_profile_id: context.runtime_profile.provider_profile_id,
      provider_profile_version: context.runtime_profile.version,
      service_profile_ref: context.transport.service_profile_ref,
      delivery_profile_ref: context.transport.delivery_profile_ref,
      delivery_policy_document: context.provider.delivery_policy_document,
      provider_display_name: context.provider.display_name,
      service_display_name: "Realtime TT&C downlink",
      delivery_display_name: "Cadence primary ingress",
      delivery_operator_summary: "Streaming to Cadence",
      route_display_name: "Primary simulator route",
      client: FakeProviderClient
    }
  end

  defp opportunity(suffix, starts_offset, ends_offset) do
    %{
      "id" => "opportunity-#{suffix}",
      "spacecraft_ref" => "SC-#{suffix}",
      "ground_station_ref" => "station-#{suffix}",
      "antenna_or_service_pool_ref" => "pool-#{suffix}",
      "service_profile_ref" => "service-realtime-ttc-downlink",
      "starts_at" => @now |> DateTime.add(starts_offset, :second) |> DateTime.to_iso8601(),
      "ends_at" => @now |> DateTime.add(ends_offset, :second) |> DateTime.to_iso8601(),
      "expires_at" => @now |> DateTime.add(18_000, :second) |> DateTime.to_iso8601(),
      "availability" => "available",
      "estimated_capacity" => %{"bytes" => 2_000_000_000},
      "synthetic" => true,
      "extensions" => %{
        "orbit_readiness" => %{"status" => "current", "valid_until" => DateTime.to_iso8601(@now)}
      }
    }
  end

  defp requirement_attrs(spacecraft_id) do
    %{
      spacecraft_id: spacecraft_id,
      service_direction: :downlink,
      contact_intent: "payload_downlink",
      earliest_start: DateTime.add(@now, 3_600, :second),
      latest_end: DateTime.add(@now, 28_800, :second),
      success_measure: :contact_count,
      minimum_duration_seconds: 600,
      preferred_duration_seconds: 900,
      minimum_data_volume_bytes: nil,
      contact_count: 2,
      minimum_separation_seconds: 0,
      priority: :high,
      provider_constraints_document: %{"allowed" => [], "excluded" => []},
      station_constraints_document: %{"allowed" => [], "excluded" => []},
      policy_constraints_document: %{},
      approval_policy_document: %{"mode" => "manual"},
      rationale: "Downlink recorder",
      metadata: %{}
    }
  end

  defp persist_provider!(organization_id, mission_id, suffix) do
    provider =
      MissionProvider.new(%{
        provider_id: "simulator-provider-#{suffix}",
        mission_id: mission_id,
        display_name: "Ground Network Simulator",
        provider_type: :simulator,
        base_url: "http://simulator.test",
        credential_ref: "config://simulator-test",
        environment_ref: "run-alpha",
        last_validated_at: @now,
        last_synced_at: @now,
        metadata: %{"control_plane" => %{"status" => "healthy"}},
        inventory_sync_document: provider_inventory()
      })

    {:ok, provider} = GroundNetworks.persist_provider(organization_id, provider)
    provider
  end

  defp provider_inventory do
    %{
      "service_profiles" => %{
        "items" => [
          %{
            "id" => "service-realtime-ttc-downlink",
            "version" => 3,
            "display_name" => "Realtime TT&C downlink",
            "direction" => "downlink",
            "state" => "active"
          }
        ]
      },
      "delivery_profiles" => %{
        "items" => [
          %{
            "id" => "delivery-cadence-primary",
            "version" => 7,
            "display_name" => "Cadence primary ingress",
            "direction" => "downlink",
            "delivery_kind" => "realtime_stream",
            "supported_service_profile_refs" => ["service-realtime-ttc-downlink"],
            "state" => "ready",
            "operator_summary" => "Streaming to Cadence",
            "diagnostics" => %{
              "protocol" => "tcp",
              "mode" => "provider_connects",
              "source_addresses" => ["127.0.0.1/32", "::1/128"],
              "host" => "127.0.0.1",
              "port" => 5100,
              "framing_family" => "ccsds_tm",
              "frame_bytes" => 1115
            }
          }
        ]
      }
    }
  end

  defp scope(organization, role, suffix) do
    user =
      User.new(%{
        user_id: "contact-plan-execution-user-#{role}-#{suffix}",
        email: "contact-plan-execution-#{role}-#{suffix}@example.test",
        display_name: "Contact Plan #{role}"
      })

    membership =
      OrganizationMembership.new(%{
        user_id: user.user_id,
        organization_id: organization.organization_id,
        role: role
      })

    Scope.new(%{
      user: user,
      organization_id: organization.organization_id,
      organization: organization,
      organization_membership: membership
    })
  end

  defp iso(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp iso(datetime) when is_binary(datetime), do: datetime
end
