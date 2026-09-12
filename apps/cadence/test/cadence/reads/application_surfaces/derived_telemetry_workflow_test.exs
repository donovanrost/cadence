defmodule Cadence.Reads.ApplicationSurfaces.DerivedTelemetryWorkflowTest do
  use Cadence.DataCase, async: false

  alias Cadence.Applications.{
    ActionDispatcher,
    ActionRequest,
    ApplicationInstallations,
    HostContext,
    SurfaceQueryRequest
  }

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}
  alias Cadence.Applications.TelemetryDecomFixtures
  alias Cadence.Auth.Scope
  alias Cadence.Control.DerivedTelemetry, as: Evaluation
  alias Cadence.DerivedTelemetry.Definition
  alias Cadence.Governance
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Reads.ApplicationSurfaces.DerivedTelemetry, as: Surface
  alias Cadence.Telemetry.PacketDefinition

  @org "org-derived-workflow"
  @mission "mission-derived-workflow"
  setup do
    persist_mission_scope(@org, @mission)

    scope = %Scope{
      actor_kind: :user,
      organization_id: @org,
      user: %{user_id: "derived-editor"},
      organization_membership: %{lifecycle_state: :active}
    }

    host = HostContext.mission(@mission)
    {:ok, installation} = ApplicationInstallations.install(scope, host, "derived_telemetry")
    %{scope: scope, host: host, installation: installation}
  end

  test "real producer reaches the public editor and its explicit reviewed action appends a version",
       c do
    page = read(c)
    assert page["definitions"]["total_count"] == 0
    assert page["values"]["total_count"] == 0
    export("empty", page)

    script =
      Path.expand(
        "../../../../../../frontend/modules/derived-telemetry/src/features/definitions/producer-check.mjs",
        __DIR__
      )

    {output, status} = System.cmd("node", [script, Jason.encode!(page)], stderr_to_stdout: true)
    assert status == 0, output
    [_, encoded] = Regex.run(~r/CADENCE_DERIVED_INPUT=([^\n]+)/, output)
    input = Jason.decode!(encoded)
    assert byte_size(input["expression"]) > 240

    assert {:ok, saved} =
             ActionDispatcher.dispatch(c.scope, c.host, %ActionRequest{
               application_key: "derived_telemetry",
               application_version: 1,
               surface_id: "manage",
               surface_version: 1,
               action_id: "save_definition",
               params: input
             })

    assert saved.version == 1

    assert {:ok, ^saved} =
             Governance.fetch_derived_definition(@org, @mission, saved.derived_definition_id, 1)

    selected = read(c, %{"definition" => saved.derived_definition_id})
    assert selected["selection"]["inspected"]["expression"] == input["expression"]
    assert selected["selection"]["current"]["version"] == 1
    export("selected", selected)
  end

  test "all definition versions and source references remain reachable with complete counts", c do
    for index <- 1..30 do
      assert {:ok, _} =
               Governance.persist_derived_definition(
                 Definition.new(%{
                   mission_id: @mission,
                   derived_definition_id: "definition-#{index}",
                   point_id: "DERIVED.p#{index}",
                   expression: "HK.voltage * 2"
                 })
               )
    end

    for version <- 2..31 do
      expression = Enum.map_join(1..60, " + ", &"HK.value#{&1}")

      assert {:ok, _} =
               Governance.persist_derived_definition(
                 Definition.new(%{
                   mission_id: @mission,
                   derived_definition_id: "definition-1",
                   point_id: "DERIVED.p1",
                   expression: expression,
                   version: version
                 })
               )
    end

    first = read(c)
    assert first["definitions"]["total_count"] == 30
    assert length(first["definitions"]["items"]) == 25
    last = read(c, %{"page" => "2"})
    assert length(last["definitions"]["items"]) == 5
    assert read(c, %{"page" => "999"})["definitions"]["page"] == 2

    current =
      read(c, %{"definition" => "definition-1", "history_page" => "2", "sources_page" => "3"})

    assert current["selection"]["current"]["version"] == 31
    assert current["selection"]["history"]["total_count"] == 31
    assert length(current["selection"]["history"]["items"]) == 6
    assert current["selection"]["sources"]["total_count"] == 60
    assert length(current["selection"]["sources"]["items"]) == 10
    historical = read(c, %{"definition" => "definition-1", "version" => "1"})
    assert historical["selection"]["inspected"]["expression"] == "HK.voltage * 2"
    assert historical["selection"]["current"]["version"] == 31

    assert read(c, %{"definition" => "definition-1", "version" => "999"})["selection"][
             "available"
           ] == false

    export("directory-last", last)
    export("history-sources", current)
    export("historical", historical)
  end

  test "latest values retain producing version and spacecraft scope across every page", c do
    definition =
      Definition.new(%{
        mission_id: @mission,
        derived_definition_id: "power-definition",
        point_id: "DERIVED.power",
        expression: "HK.counter * 2"
      })

    assert {:ok, _} = Governance.persist_derived_definition(definition)

    packet =
      PacketDefinition.new(%{
        mission_id: @mission,
        packet_definition_id: "derived-input",
        packet_name: "HK",
        apid: 42,
        fields: [%{name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}]
      })

    binding =
      BindingSet.new(%{
        mission_id: @mission,
        binding_set_id: "derived-inputs",
        version: 1,
        rules: [
          BindingRule.new(%{
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 42,
            handler_configuration: packet
          })
        ]
      })

    assert {:ok, _} = Governance.persist_binding_set(binding)

    spacecraft =
      Enum.map(1..27, fn i ->
        TelemetryDecomFixtures.persist_spacecraft!(@org, @mission, display_name: "Vehicle #{i}")
      end)

    for {craft, index} <- Enum.with_index([nil | spacecraft], 1) do
      raw = <<0::3, 0::1, 0::1, 42::11, 3::2, index::14, 1::16, index::16>>

      assert {:ok, _} =
               Cadence.process_and_persist_telemetry_ingress(
                 RawEvidence.new(%{
                   mission_id: @mission,
                   spacecraft_id: craft && craft.spacecraft_id,
                   raw: raw,
                   receipt_time: DateTime.from_unix!(1_700_000_400 + index)
                 }),
                 binding.binding_set_id,
                 1
               )
    end

    assert {:ok, _} = Evaluation.evaluate(@mission)

    assert {:ok, _} =
             Governance.persist_derived_definition(%{
               definition
               | version: 2,
                 expression: "HK.counter * 3"
             })

    first = read(c)
    assert first["values"]["total_count"] == 28
    assert length(first["values"]["items"]) == 25
    last = read(c, %{"values_page" => "2", "spacecraft_page" => "2"})
    assert length(last["values"]["items"]) == 3
    assert last["spacecraft"]["total_count"] == 27
    assert length(last["spacecraft"]["items"]) == 2

    assert Enum.all?(
             first["values"]["items"] ++ last["values"]["items"],
             &(&1["definition_version"] == 1)
           )

    mission = read(c, %{"spacecraft" => "mission"})

    assert [
             %{
               "spacecraft_id" => nil,
               "definition_id" => "power-definition",
               "definition_version" => 1
             }
           ] = mission["values"]["items"]

    [craft | _] = spacecraft
    scoped = read(c, %{"spacecraft" => craft.spacecraft_id})
    assert [%{"spacecraft_id" => id, "value" => "4"}] = scoped["values"]["items"]
    assert id == craft.spacecraft_id
    inspected = read(c, %{"definition" => "power-definition", "version" => "1"})
    assert inspected["selection"]["inspected"]["version"] == 1
    assert inspected["selection"]["current"]["version"] == 2
    export("values-last", last)
    export("values-scoped", scoped)
    export("values-producing-version", inspected)
  end

  test "scope, installation and route query boundaries reject foreign evidence", c do
    assert {:error, _} = Surface.load(%{c.scope | organization_id: "foreign"}, c.host, request())

    assert {:error, :invalid_application_surface_query} =
             Surface.load(c.scope, c.host, request(%{"page" => "invalid"}))

    assert {:error, :invalid_application_surface_query} =
             Surface.load(c.scope, c.host, request(%{"organization_id" => "foreign"}))

    assert {:error, _} = Surface.load(c.scope, c.host, request(%{"spacecraft" => "foreign"}))
    assert {:ok, _} = ApplicationInstallations.disable(c.scope, c.host, "derived_telemetry")
    assert {:error, :application_installation_disabled} = Surface.load(c.scope, c.host, request())
  end

  defp read(c, params \\ %{}) do
    assert {:ok, %{"data" => page}} = Surface.load(c.scope, c.host, request(params))
    page
  end

  defp request(params \\ %{}),
    do: %SurfaceQueryRequest{
      application_key: "derived_telemetry",
      application_version: 1,
      surface_id: "manage",
      surface_version: 1,
      query_id: "cadence.derived_telemetry.manage",
      query_version: 1,
      params: params
    }

  defp export(name, page) do
    if dir = System.get_env("CADENCE_DERIVED_FIXTURES") do
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, name <> ".json"), Jason.encode!(%{page: page}))
    end
  end
end
