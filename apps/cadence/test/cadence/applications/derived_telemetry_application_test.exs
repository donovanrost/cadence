defmodule Cadence.Applications.DerivedTelemetryApplicationTest do
  use Cadence.DataCase, async: false

  alias Cadence.Applications.{
    ActionDispatcher,
    ActionFailure,
    ActionRequest,
    ApplicationInstallations,
    HostContext
  }

  alias Cadence.Auth.Scope
  alias Cadence.Governance
  alias Cadence.Repo
  alias Ecto.Adapters.{SQL, SQL.Sandbox}

  @organization_id "org-derived-telemetry-application"
  @mission_id "mission-derived-telemetry-application"

  setup do
    persist_mission_scope(@organization_id, @mission_id)

    scope = %Scope{
      actor_kind: :user,
      organization_id: @organization_id,
      user: %{user_id: "derived-telemetry-operator"},
      organization_membership: %{lifecycle_state: :active}
    }

    host_context = HostContext.mission(@mission_id)

    assert {:ok, _installation} =
             ApplicationInstallations.install(scope, host_context, "derived_telemetry")

    %{scope: scope, host_context: host_context}
  end

  test "dispatches a declared action into governed immutable definition versions", context do
    request = %ActionRequest{
      application_key: "derived_telemetry",
      application_version: 1,
      surface_id: "manage",
      surface_version: 1,
      action_id: "save_definition",
      params: %{
        "expected_version" => 0,
        "expected_definition_id" => nil,
        "point_id" => "DERIVED.bus_power",
        "point_name" => "Bus power",
        "expression" => "HK.voltage * HK.current"
      }
    }

    assert {:ok, first_definition} =
             ActionDispatcher.dispatch(context.scope, context.host_context, request)

    assert first_definition.version == 1
    assert first_definition.point_name == "Bus power"
    assert first_definition.source_point_ids == ["HK.voltage", "HK.current"]

    revised_request = %ActionRequest{
      request
      | params: %{
          "expected_version" => 1,
          "expected_definition_id" => first_definition.derived_definition_id,
          "point_id" => "DERIVED.bus_power",
          "point_name" => "Revised bus power",
          "expression" => "HK.voltage * HK.current * 0.95"
        }
    }

    assert {:ok, revised_definition} =
             ActionDispatcher.dispatch(context.scope, context.host_context, revised_request)

    assert revised_definition.derived_definition_id == first_definition.derived_definition_id
    assert revised_definition.version == 2
    assert revised_definition.point_name == "Revised bus power"

    assert [latest_definition] = Governance.list_derived_definitions(@mission_id)
    assert latest_definition.version == 2
    assert latest_definition.expression == "HK.voltage * HK.current * 0.95"
  end

  test "rejects declared actions without mission authority", context do
    unauthorized_scope = %Scope{
      actor_kind: :user,
      organization_id: @organization_id,
      user: %{user_id: "unauthorized-derived-operator"}
    }

    request = %ActionRequest{
      application_key: "derived_telemetry",
      application_version: 1,
      surface_id: "manage",
      surface_version: 1,
      action_id: "save_definition",
      params: %{
        "point_id" => "DERIVED.unauthorized",
        "expression" => "HK.value * 2"
      }
    }

    assert {:error, :forbidden} =
             ActionDispatcher.dispatch(unauthorized_scope, context.host_context, request)

    assert Governance.list_derived_definitions(@mission_id) == []
  end

  test "returns typed field failures from the application adapter", context do
    request = %ActionRequest{
      application_key: "derived_telemetry",
      application_version: 1,
      surface_id: "manage",
      surface_version: 1,
      action_id: "save_definition",
      params: %{"point_id" => "DERIVED.missing_expression", "expression" => ""}
    }

    assert {:error,
            %ActionFailure{
              code: "required_field",
              field: "expression",
              message: "Expression is required."
            }} = ActionDispatcher.dispatch(context.scope, context.host_context, request)

    assert Governance.list_derived_definitions(@mission_id) == []
  end

  test "reviewed edits reject stale versions and preserve the stored immutable winner", c do
    request = %ActionRequest{
      application_key: "derived_telemetry",
      application_version: 1,
      surface_id: "manage",
      surface_version: 1,
      action_id: "save_definition",
      params: %{
        "point_id" => "DERIVED.power",
        "expression" => "HK.voltage * 2",
        "expected_definition_id" => nil,
        "expected_version" => 0
      }
    }

    assert {:ok, first} = ActionDispatcher.dispatch(c.scope, c.host_context, request)

    assert {:error, %ActionFailure{code: "review_conflict"}} =
             ActionDispatcher.dispatch(c.scope, c.host_context, request)

    edit = %{
      request
      | params:
          Map.merge(request.params, %{
            "expected_version" => 1,
            "expected_definition_id" => first.derived_definition_id,
            "expression" => "HK.voltage * 3"
          })
    }

    assert {:ok, second} = ActionDispatcher.dispatch(c.scope, c.host_context, edit)
    assert second.version == 2

    assert {:error, %ActionFailure{code: "review_conflict"}} =
             ActionDispatcher.dispatch(c.scope, c.host_context, edit)

    assert {:error, :derived_definition_version_conflict} =
             Governance.persist_derived_definition(%{second | expression: "HK.voltage * 4"})

    assert {:ok, ^second} =
             Governance.fetch_derived_definition(
               @organization_id,
               @mission_id,
               second.derived_definition_id,
               2
             )

    assert {:ok, ^first} =
             Governance.fetch_derived_definition(
               @organization_id,
               @mission_id,
               first.derived_definition_id,
               1
             )

    assert {:ok, ^second} = Governance.persist_derived_definition(second)

    assert {:error, :derived_definition_not_found} =
             Governance.fetch_derived_definition(
               "foreign",
               @mission_id,
               first.derived_definition_id,
               1
             )

    assert Governance.derived_definitions_page("foreign", @mission_id, []) == %{
             items: [],
             total_count: 0,
             page: 1
           }
  end

  test "saving requires the exact reviewed definition identity", c do
    request = %ActionRequest{
      application_key: "derived_telemetry",
      application_version: 1,
      surface_id: "manage",
      surface_version: 1,
      action_id: "save_definition",
      params: %{"point_id" => "DERIVED.power", "expression" => "HK.voltage * 2"}
    }

    assert {:error, %ActionFailure{code: "review_required"}} =
             ActionDispatcher.dispatch(c.scope, c.host_context, request)

    request = %{
      request
      | params:
          Map.merge(request.params, %{"expected_version" => 0, "expected_definition_id" => nil})
    }

    assert {:ok, _first} = ActionDispatcher.dispatch(c.scope, c.host_context, request)

    wrong = %{
      request
      | params:
          Map.merge(request.params, %{
            "expected_version" => 1,
            "expected_definition_id" => "wrong"
          })
    }

    assert {:error, %ActionFailure{code: "review_conflict"}} =
             ActionDispatcher.dispatch(c.scope, c.host_context, wrong)
  end

  test "independent concurrent first saves preserve exactly one immutable reviewed winner" do
    suffix = System.unique_integer([:positive])
    org = "derived-race-org-#{suffix}"
    mission = "derived-race-mission-#{suffix}"

    independent(fn ->
      persist_mission_scope(org, mission)

      try do
        run_reviewed_race(org, mission)
      after
        SQL.query!(
          Repo,
          "DELETE FROM governed_derived_telemetry_definitions WHERE organization_id = $1 AND mission_id = $2",
          [org, mission]
        )

        SQL.query!(Repo, "DELETE FROM missions WHERE organization_id = $1 AND mission_id = $2", [
          org,
          mission
        ])

        SQL.query!(Repo, "DELETE FROM organizations WHERE organization_id = $1", [org])
      end
    end)
    |> Task.await(15_000)
  end

  defp run_reviewed_race(org, mission) do
    parent = self()

    attrs = %{
      point_id: "DERIVED.concurrent",
      point_name: "Concurrent",
      expression: "HK.voltage * 2",
      expected_definition_id: nil
    }

    first =
      independent(fn ->
        Repo.transaction(fn ->
          result = Governance.append_derived_definition(org, mission, attrs, 0)
          send(parent, {:first_saved, self(), result})

          receive do
            :release -> result
          after
            5_000 -> raise "first save was not released"
          end
        end)
      end)

    assert_receive {:first_saved, owner, {:ok, winner}}, 2_000

    second =
      independent(fn ->
        %{rows: [[pid]]} = SQL.query!(Repo, "SELECT pg_backend_pid()", [])
        send(parent, {:second_backend, pid})

        Governance.append_derived_definition(
          org,
          mission,
          %{attrs | expression: "HK.voltage * 3"},
          0
        )
      end)

    try do
      assert_receive {:second_backend, pid}, 2_000
      assert wait_for_derived_lock(pid, 100)
      send(owner, :release)
      assert {:ok, {:ok, ^winner}} = Task.await(first)
      assert {:error, :derived_definition_version_conflict} = Task.await(second)
      assert [^winner] = Governance.list_derived_definitions(org, mission)

      assert %{total_count: 1, items: [^winner]} =
               Governance.derived_definition_history(
                 org,
                 mission,
                 winner.derived_definition_id,
                 1
               )
    after
      send(owner, :release)
      Task.shutdown(first)
      Task.shutdown(second)
    end
  end

  defp independent(operation) do
    Task.async(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)

      try do
        operation.()
      after
        Sandbox.checkin(Repo)
      end
    end)
  end

  defp wait_for_derived_lock(_pid, 0), do: false

  defp wait_for_derived_lock(pid, attempts) do
    %{rows: [[waiting]]} =
      SQL.query!(
        Repo,
        "SELECT EXISTS (SELECT 1 FROM pg_locks WHERE pid = $1 AND locktype = 'advisory' AND NOT granted)",
        [pid]
      )

    if waiting do
      true
    else
      Process.sleep(10)
      wait_for_derived_lock(pid, attempts - 1)
    end
  end
end
