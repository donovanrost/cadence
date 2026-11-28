defmodule Cadence.Control.MonitoringApplyTest do
  @moduledoc """
  ADR-020 P3 slice M2 (#451, the design agreed on #1106): a monitoring change set's apply records
  the next authored version, moves every craft to its composition's head revision in one
  generation with no pin move, and leaves each craft's configuration and command plan as they
  were. A refused set leaves nothing behind.
  """
  use Cadence.RuntimeCase, async: false

  alias Cadence.Applications.SpacecraftConfiguration.{Active, Drafts, Review}
  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Catalog.SpacecraftConfigurationInput
  alias Cadence.Configuration.Status
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Control.Configuration
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Management.Activations
  alias Cadence.MissionModels
  alias Cadence.MissionModels.{AuthoredHead, AuthoredLayer}
  alias Cadence.Missions
  alias Cadence.SourceEndpoints

  setup do
    org = "org-monitoring-apply-#{System.unique_integer([:positive])}"
    mid = "mission-monitoring-apply-#{System.unique_integer([:positive])}"
    {craft, catalog, _endpoint} = Fixtures.setup_imported_mission!(org, mid)
    scope = Fixtures.user_scope(org, "admin")
    policy = ActivationPolicy.load(org, mid)

    {:ok, _} =
      ActivationPolicy.save(scope, mid, policy.token, %{
        "value" => %{"approval_requirement" => "direct"}
      })

    c = %{org: org, mid: mid, scope: scope, craft: craft, catalog: catalog.catalog_revision_id}
    configure!(c)
    Map.put(c, :before, entry!(c))
  end

  test "a monitoring apply moves the fleet to the head and changes nothing else", c do
    {:ok, _applied} = apply!(c, [create_op(c, "Bus temperature", 35)])

    assert %{version: 1, approval: "direct"} = AuthoredHead.head(c.org, c.mid)

    after_entry = entry!(c)
    revision = after_entry["mission_model"]["revision_id"]

    refute revision == c.before["mission_model"]["revision_id"]
    assert MissionModels.effective_statuses(c.org, c.mid, [revision])[revision] == :approved

    # The craft's configuration is untouched: no assignment row for a monitoring change.
    assert after_entry["configuration_revision_id"] == c.before["configuration_revision_id"]

    # Option B: the command plan's identity doesn't move.
    assert command_plan(after_entry) == command_plan(c.before)

    # And the head's monitoring plan carries the mission policy.
    {:ok, %{monitoring: monitoring}} = MissionModels.fetch_runtime_plans(c.org, c.mid, revision)

    assert Enum.any?(
             monitoring.plan["policies"],
             &(&1["origin"] == "mission_layer" and &1["scope"] == "mission")
           )
  end

  test "a monitoring apply leaves every binding's content as it was, ids aside", c do
    before = bindings!(c)
    {:ok, _applied} = apply!(c, [create_op(c, "Bus voltage", 30)])

    # Content equal: only the revision-derived ids may differ (commanding's condition on #1106).
    assert bindings!(c) == before
  end

  test "an apply refused at commit answers the closed error, never retries" do
    refused = %Postgrex.Error{postgres: %{constraint: "mission_model_authored_versions_applied"}}

    assert Configuration.committed(fn -> raise refused end) ==
             {:error, :authored_version_not_applied}

    unknown = %Postgrex.Error{
      postgres: %{
        constraint: "something_else",
        code: :check_violation,
        pg_code: "23514",
        severity: "ERROR",
        message: "another check"
      }
    }

    assert_raise Postgrex.Error, fn -> Configuration.committed(fn -> raise unknown end) end
  end

  test "a set refused at submit leaves no version, no head and the fleet as it was", c do
    bad = put_in(create_op(c, "Nowhere", 10).document["parameter"], "/no/such/point")

    assert {:error, _refused} = apply!(c, [bad])

    assert AuthoredHead.head(c.org, c.mid) == nil
    assert entry!(c) == c.before
  end

  test "two monitoring sets in review on one policy can't both apply", c do
    {:ok, _applied} = apply!(c, [create_op(c, "Shared limit", 35)])
    independent!(c)
    reviewer = Fixtures.user_scope(c.org, "reviewer")

    {:ok, first} = stage_and_submit!(c, update_op("Shared limit", 30))
    {:ok, second} = stage_and_submit!(c, update_op("Shared limit", 25))

    assert {:ok, %{state: :applied}} = approve(reviewer, c, first)
    # The policy changed since the second set's base: it must restage, never overwrite.
    assert {:error, {:checks_failed, preview}} = approve(reviewer, c, second)
    conflicts = Enum.find(preview.checks, &(&1.key == "conflicts"))
    assert Enum.any?(conflicts.items, &(&1.reason == :value_changed))
    assert %{version: 2} = AuthoredHead.head(c.org, c.mid)
  end

  test "a definition that won't compile is a NO-GO before anything applies", c do
    op =
      update_in(create_op(c, "Dangling override", 20).document, fn document ->
        Map.merge(document, %{"overrides" => "/monitoring/none", "spacecraft_ids" => ["sc-1"]})
      end)

    assert {:error, {:holds_blocking, preview}} = apply!(c, [op])
    holds = Enum.flat_map(preview.checks, &Map.get(&1, :items, []))

    assert Enum.any?(
             holds,
             &(&1[:reason] == :monitoring_compile_no_go and is_binary(&1.details.composition_id))
           )

    assert AuthoredHead.head(c.org, c.mid) == nil
  end

  defp independent!(c) do
    policy = ActivationPolicy.load(c.org, c.mid)

    {:ok, _} =
      ActivationPolicy.save(c.scope, c.mid, policy.token, %{
        "value" => %{"approval_requirement" => "independent"}
      })
  end

  defp update_op(name, upper) do
    %{
      kind: "monitoring_policy",
      action: "update",
      entity_id: AuthoredLayer.entity_id(name),
      changes: [
        %{
          path: "default_rules",
          value: [%{"kind" => "range", "upper" => upper, "severity" => "warning"}]
        }
      ]
    }
  end

  defp stage_and_submit!(c, op) do
    with {:ok, staged} <- Configuration.stage(c.scope, c.mid, %{summary: "Edit"}, [op]),
         {:ok, %{change_set: %{version: version}}} <-
           Configuration.current(c.scope, c.mid, "monitoring"),
         {:ok, %{state: :in_review}} <-
           Configuration.submit(c.scope, c.mid, staged.change_set_id, %{
             reason: "Tighten the shared limit",
             expected_version: version
           }) do
      {:ok, staged.change_set_id}
    end
  end

  defp approve(reviewer, c, change_set_id) do
    {:ok, set} = Status.change_set(c.mid, change_set_id)

    Configuration.review(reviewer, c.mid, change_set_id, :approve, %{
      comment: "Agreed",
      expected_version: set.version
    })
  end

  defp create_op(c, name, upper) do
    %{
      kind: "monitoring_policy",
      action: "create",
      document: %{
        "name" => name,
        "parameter_id" => parameter_id!(c),
        "policy_kind" => "limit",
        "default_rules" => [%{"kind" => "range", "upper" => upper, "severity" => "warning"}]
      }
    }
  end

  defp apply!(c, ops) do
    with {:ok, staged} <- Configuration.stage(c.scope, c.mid, %{summary: "Monitoring"}, ops),
         {:ok, %{change_set: %{version: version}}} <-
           Configuration.current(c.scope, c.mid, "monitoring") do
      Configuration.submit(c.scope, c.mid, staged.change_set_id, %{
        reason: "Tighten the bus temperature limits",
        expected_version: version
      })
    end
  end

  defp parameter_id!(c) do
    {:ok, revision} =
      MissionModels.fetch_revision(c.org, c.mid, c.before["mission_model"]["revision_id"])

    revision.declarations
    |> Map.values()
    |> Enum.find(&(&1.kind == :parameter))
    |> Map.fetch!(:semantic_id)
  end

  defp entry!(c) do
    {:ok, mission} = Missions.fetch_mission(c.org, c.mid)
    {:ok, %{entries: entries}} = Active.load(mission)
    Map.fetch!(entries, c.craft.spacecraft_id)
  end

  # The active binding set's content for the craft, with the ids that embed the revision dropped.
  defp bindings!(c) do
    {:ok, mission} = Missions.fetch_mission(c.org, c.mid)
    {:ok, %{binding_set: set}} = Active.load(mission)

    {Enum.map(set.capability_instances, &without_ids/1), Enum.map(set.rules, &without_ids/1)}
  end

  @revision_ids ~w(capability_instance_id binding_rule_id rule_id mission_model_revision_id
    inserted_at updated_at)a

  defp without_ids(%_{} = struct), do: struct |> Map.from_struct() |> without_ids()

  defp without_ids(%{} = map),
    do:
      map
      |> Map.drop(@revision_ids ++ Enum.map(@revision_ids, &Atom.to_string/1))
      |> Map.new(fn {k, v} -> {k, without_ids(v)} end)

  defp without_ids(list) when is_list(list), do: Enum.map(list, &without_ids/1)
  defp without_ids(value), do: value

  defp command_plan(entry) do
    command = get_in(entry, ["mission_model", "plans", "command"]) || %{}
    Map.take(command, ["plan_id", "content_sha256", "target_contract_version"])
  end

  # An active generation for the fixture's craft on its catalog (as #678's test does).
  defp configure!(c) do
    {:ok, mission} = Missions.fetch_mission(c.org, c.mid)
    current = Drafts.snapshot(mission, c.craft)

    endpoint =
      SourceEndpoints.list_source_endpoints(c.org, c.mid)
      |> Enum.find(&(&1.spacecraft_id == c.craft.spacecraft_id))

    document =
      Map.merge(SpacecraftConfigurationInput.empty(), %{
        "catalog_revision_id" => c.catalog,
        "telemetry_enabled" => true,
        "commanding_enabled" => true,
        "handled_apids" => [42],
        "telemetry_source_endpoint_id" => endpoint && endpoint.source_endpoint_id
      })

    :ok = Fixtures.change_set_switches!(c.org, c.mid, c.craft.spacecraft_id, document)
    {:ok, _} = Drafts.save(c.scope, c.mid, c.craft.spacecraft_id, current.token, document)
    token = Drafts.snapshot(mission, c.craft).token

    {:ok, request} = Review.request_many(c.scope, c.mid, %{c.craft.spacecraft_id => token})
    {:ok, approved} = Activations.fetch_approved(request.activation_request_id)
    {:ok, %{status: :succeeded}} = ControlActivations.execute(approved)
  end
end
