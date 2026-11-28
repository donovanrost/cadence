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
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Control.Configuration
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Management.Activations
  alias Cadence.MissionModels
  alias Cadence.MissionModels.AuthoredHead

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

  test "a set refused at submit leaves no version, no head and the fleet as it was", c do
    bad = put_in(create_op(c, "Nowhere", 10).document["parameter"], "/no/such/point")

    assert {:error, _refused} = apply!(c, [bad])

    assert AuthoredHead.head(c.org, c.mid) == nil
    assert entry!(c) == c.before
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
    {:ok, mission} = Cadence.Missions.fetch_mission(c.org, c.mid)
    {:ok, %{entries: entries}} = Active.load(mission)
    Map.fetch!(entries, c.craft.spacecraft_id)
  end

  defp command_plan(entry) do
    command = get_in(entry, ["mission_model", "plans", "command"]) || %{}
    Map.take(command, ["plan_id", "content_sha256", "target_contract_version"])
  end

  # An active generation for the fixture's craft on its catalog (as #678's test does).
  defp configure!(c) do
    {:ok, mission} = Cadence.Missions.fetch_mission(c.org, c.mid)
    current = Drafts.snapshot(mission, c.craft)

    endpoint =
      Cadence.SourceEndpoints.list_source_endpoints(c.org, c.mid)
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
