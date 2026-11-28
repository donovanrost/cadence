defmodule Cadence.Commanding.MonitoringApplyCommandingTest do
  @moduledoc """
  #1107, through M2's real apply path (a monitoring change set applied by the activation policy):
  a monitoring apply moves the craft to its composition's head revision, and leaves what commands
  resolve against as it was. So the catalog token is equal, a create in flight (a preflight shown
  before the apply) still submits, and a request already queued still resolves its command plan
  for release instead of failing closed.
  """
  use Cadence.RuntimeCase, async: false

  import Ecto.Query

  alias Cadence.Applications.SpacecraftConfiguration.{Active, Drafts, Review}
  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Catalog.SpacecraftConfigurationInput
  alias Cadence.CommandGroupFixtures
  alias Cadence.Commanding.Groups.GroupStore
  alias Cadence.Commanding.RequestValidation
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Control.Commanding.{GroupDecision, GroupSubmission}
  alias Cadence.Control.Configuration
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Management.Activations
  alias Cadence.MissionModels
  alias Cadence.Missions
  alias Cadence.Reads.CommandCatalog
  alias Cadence.Reads.CommandPreflight
  alias Cadence.Reads.MissionModels.ActiveBasis
  alias Cadence.SourceEndpoints
  alias Cadence.SourceEndpoints.SourceEndpointRow

  @yaml """
  packets:
    - name: HEALTH
      apid: 42
      items:
        - name: mode
          data_type: uint
          bit_offset: 0
          bit_size: 8
  commands:
    - name: SET_MODE
      opcode: 1
      parameters:
        - name: value
          data_type: uint
          required: true
          bit_offset: 0
          bit_length: 8
    - name: RESET_UNIT
      opcode: 2
      is_hazardous: true
      hazard_description: Resets the unit
      requires_confirmation: true
      parameters:
        - name: value
          data_type: uint
          required: true
          bit_offset: 0
          bit_length: 8
  """

  setup do
    org = "org-monitoring-commanding-#{System.unique_integer([:positive])}"
    mid = "mission-monitoring-commanding-#{System.unique_integer([:positive])}"
    {craft, catalog, endpoint} = Fixtures.setup_imported_mission!(org, mid, yaml: @yaml)
    scope = Fixtures.user_scope(org, "admin")
    policy = ActivationPolicy.load(org, mid)

    {:ok, _} =
      ActivationPolicy.save(scope, mid, policy.token, %{
        "value" => %{"approval_requirement" => "direct"}
      })

    c = %{
      org: org,
      mid: mid,
      scope: scope,
      craft: craft,
      endpoint: endpoint,
      catalog: catalog.catalog_revision_id
    }

    # A commandable endpoint has a spacecraft id (SCID).
    Repo.update_all(
      from(e in SourceEndpointRow, where: e.source_endpoint_id == ^endpoint.source_endpoint_id),
      set: [scid: 1]
    )

    configure!(c)
    CommandGroupFixtures.commandable_pass!(org, mid, craft.spacecraft_id)
    {:ok, %{commands: commands}} = CommandCatalog.list(org, mid)
    ids = Map.new(commands, &{&1.name, &1.id})

    Map.merge(c, %{
      command_id: ids["SET_MODE"],
      hazardous_id: ids["RESET_UNIT"],
      operator: CommandGroupFixtures.operator!(c),
      approver: CommandGroupFixtures.operator!(c, "Approver"),
      before: entry!(c)
    })
  end

  defp token(c) do
    {:ok, token} =
      Repo.transaction(fn ->
        {:ok, snapshot} = ActiveBasis.command_catalog_snapshot(c.org, c.mid)
        snapshot.token
      end)

    token
  end

  defp draft(c) do
    %{
      title: "Routine",
      targets: [
        %{spacecraft_id: c.craft.spacecraft_id, source_endpoint_id: c.endpoint.source_endpoint_id}
      ],
      commands: [%{command_id: c.command_id, argument_values: %{"value" => 1}}],
      priority: 3
    }
  end

  defp hazardous(c) do
    %{
      draft(c)
      | commands: [%{command_id: c.hazardous_id, argument_values: %{"value" => 1}}]
    }
    |> Map.put(:log_entry, "Reset")
  end

  defp actor(c), do: %{"actor_kind" => "user", "user_id" => c.operator.user.user_id}

  test "a monitoring apply leaves the token, a create in flight and a queued request as they were",
       c do
    before = token(c)
    draft = draft(c)

    # A create in flight: its preflight is shown, then the apply lands, then it submits.
    {:ok, preflight} = CommandPreflight.run(c.org, c.mid, actor(c), draft)
    assert preflight.valid?, inspect({preflight.targets, preflight.checks}, limit: 12)

    # A request already queued on the base revision.
    {:ok, queued} =
      GroupSubmission.submit(c.operator, c.mid, draft,
        preflight_digest: preflight.digest,
        request_validation: preflight.request_validation
      )

    [member] = GroupStore.members(c.org, c.mid, queued.command_group_id)
    base_revision = c.before["mission_model"]["revision_id"]
    assert member.mission_model_revision_id == base_revision

    # A group waiting for its second GO.
    pending_draft = hazardous(c)
    {:ok, pending_pre} = CommandPreflight.run(c.org, c.mid, actor(c), pending_draft)

    {:ok, pending} =
      GroupSubmission.submit(c.operator, c.mid, pending_draft,
        preflight_digest: pending_pre.digest,
        request_validation: pending_pre.request_validation
      )

    assert pending.state == :approval_pending

    {:ok, _applied} = apply!(c)

    head_entry = entry!(c)
    refute head_entry["mission_model"]["revision_id"] == base_revision

    # What commands resolve against hasn't moved.
    assert token(c) == before

    # The create in flight still submits (a second group, on the same preflight).
    assert {:ok, %{state: :queued}} =
             GroupSubmission.submit(c.operator, c.mid, draft, preflight_digest: preflight.digest)

    # The pending GO still holds: a second operator gives it.
    assert {:ok, %{state: :queued}} =
             GroupDecision.decide(c.approver, c.mid, pending.command_group_id, %{
               kind: :go,
               expected_review: GroupDecision.review_token(pending)
             })

    # And the queued request resolves its command plan on the head (it doesn't fail closed).
    assert {:ok, %{runtime_plan_id: plan_id}} =
             RequestValidation.resolve_basis_of(c.org, c.mid, member)

    assert plan_id == RequestValidation.pinned_plan_id(member)
  end

  defp apply!(c) do
    op = %{
      kind: "monitoring_policy",
      action: "create",
      document: %{
        "name" => "Bus temperature",
        "parameter_id" => parameter_id!(c),
        "policy_kind" => "limit",
        "default_rules" => [%{"kind" => "range", "upper" => 35, "severity" => "warning"}]
      }
    }

    with {:ok, staged} <- Configuration.stage(c.scope, c.mid, %{summary: "Monitoring"}, [op]),
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

  # An active generation for the fixture's craft on its catalog, commanding on (as M2's test does).
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
