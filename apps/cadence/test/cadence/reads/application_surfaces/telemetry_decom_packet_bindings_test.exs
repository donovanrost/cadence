defmodule Cadence.Reads.ApplicationSurfaces.TelemetryDecomPacketBindingsTest do
  use Cadence.DataCase, async: false

  alias Cadence.Applications.{
    ActionDispatcher,
    ActionFailure,
    ActionRequest,
    ApplicationInstallations,
    HostContext,
    PacketBindings,
    Registry,
    SurfaceQueryRequest,
    TelemetryDecom,
    TelemetryDecomFixtures
  }

  alias Cadence.Reads.ApplicationSurfaces
  alias Cadence.Reads.ApplicationSurfaces.TelemetryDecom.PacketBindings, as: PacketSurface

  @organization_id "org-packet-feature"
  @mission_id "mission-packet-feature"

  setup do
    {spacecraft, revision, endpoint} =
      TelemetryDecomFixtures.setup_imported_mission!(@organization_id, @mission_id)

    scope = TelemetryDecomFixtures.user_scope(@organization_id, "packet-feature")
    host = HostContext.spacecraft(@mission_id, spacecraft.spacecraft_id)
    {:ok, installation} = ApplicationInstallations.install(scope, host, "telemetry_decom")

    %{
      scope: scope,
      host: host,
      spacecraft: spacecraft,
      revision: revision,
      endpoint: endpoint,
      installation: installation
    }
  end

  test "unconfigured packet read uses the trusted scoped contribution and rejects invalid query or scope",
       c do
    {:ok, definition} = Registry.fetch_available("telemetry_decom")
    {:ok, surface} = Registry.fetch_surface(definition, :spacecraft, "packet_bindings")

    assert {:ok, %{"data" => page}} =
             ApplicationSurfaces.load(c.scope, c.host, "telemetry_decom", 1, surface)

    assert page["configuration"] == nil
    assert page["status"] == "unconfigured"
    assert page["context"]["actor_id"] == c.scope.user.user_id

    assert page["input"] == %{
             "id" => "telemetry-fields",
             "version" => 1,
             "minimum" => 1,
             "maximum" => 512
           }

    assert {:error, :invalid_application_surface_query} =
             PacketSurface.load(c.scope, c.host, query(%{"page" => "1x"}))

    assert {:error, :invalid_application_surface_query} =
             PacketSurface.load(c.scope, c.host, query(%{"mission_id" => "foreign"}))

    assert {:error, _} =
             PacketSurface.load(%{c.scope | organization_id: "foreign"}, c.host, query())
  end

  test "packets after the previous 512 cap and every resource remain reachable with complete counts",
       c do
    yaml = large_catalog()

    revision =
      TelemetryDecomFixtures.persist_imported_revision!(@organization_id, @mission_id, yaml: yaml)

    configure(c, revision, [0])
    first = read(c)

    assert first["summary"] == %{
             "packet_count" => 530,
             "compatible_packet_count" => 530,
             "selected_count" => 1,
             "selected_field_count" => 60
           }

    assert length(first["packets"]["items"]) == 25
    assert first["packets"]["total_count"] == 530
    final = read(c, %{"page" => "22"})
    assert length(final["packets"]["items"]) == 5
    assert List.last(final["packets"]["items"])["apid"] == 529
    assert final["selection"] == first["selection"]
    assert final["review_token"] == first["review_token"]
    [packet | _] = first["packets"]["items"]
    detail = read(c, %{"packet" => packet["id"], "resource_page" => "3"})
    assert detail["detail"]["resources"]["total_count"] == 60
    assert length(detail["detail"]["resources"]["items"]) == 10
    export_fixture("large-first", first)
    export_fixture("large-final", final)
    export_fixture("large-detail", detail)
    configure(c, revision, Enum.to_list(0..529))
    oversized = read(c)
    assert oversized["selection"]["total_count"] == 530
    assert oversized["selection"]["complete"] == false
    assert length(oversized["selection"]["ids"]) == 512
    assert oversized["summary"]["selected_field_count"] == 589
    export_fixture("legacy-oversized", oversized)
  end

  test "endpoint pages include mission endpoints and exclude another spacecraft even beyond 128 rows",
       c do
    configure(c)

    for index <- 1..130 do
      TelemetryDecomFixtures.persist_source_endpoint!(
        @organization_id,
        @mission_id,
        c.spacecraft.spacecraft_id,
        display_name: "Endpoint #{index}"
      )
    end

    TelemetryDecomFixtures.persist_source_endpoint!(@organization_id, @mission_id, nil,
      display_name: "Mission shared"
    )

    other =
      TelemetryDecomFixtures.persist_spacecraft!(@organization_id, @mission_id,
        display_name: "Other"
      )

    foreign =
      TelemetryDecomFixtures.persist_source_endpoint!(
        @organization_id,
        @mission_id,
        other.spacecraft_id,
        display_name: "Foreign only"
      )

    page = read(c, %{"endpoint_page" => "6"})
    assert page["endpoints"]["total_count"] == 132
    assert length(page["endpoints"]["items"]) == 7
    refute Enum.any?(page["endpoints"]["items"], &(&1["id"] == foreign.source_endpoint_id))
    assert read(c, %{"endpoint_q" => "Foreign only"})["endpoints"]["total_count"] == 0
    assert read(c, %{"endpoint_q" => "Mission shared"})["endpoints"]["total_count"] == 1
    assert read(c, %{"endpoint_page" => "999"})["endpoints"]["page"] == 6
    export_fixture("endpoints-final", page)
  end

  test "producer to public module to action persists selection and pins both Manage revision and packet version",
       c do
    configure(c)
    page = read(c)
    export_fixture("configured", page)
    input = client_input(page)
    assert input["expected_review"] == page["review_token"]
    assert input["expected_configuration_version"] == 0
    assert {:ok, saved} = dispatch(c, input)

    assert {:ok, [stored]} =
             PacketBindings.list(c.scope, c.host, c.installation.application_installation_id)

    assert stored.packet_binding_configuration_id == saved.packet_binding_configuration_id
    assert Enum.map(stored.bindings, & &1.packet_id) == input["selected_packet_ids"]
    current = read(c)
    assert current["configuration"]["version"] == 1
    export_fixture("saved", current)
    assert {:error, %ActionFailure{code: "review_conflict"}} = dispatch(c, input)

    other =
      TelemetryDecomFixtures.persist_imported_revision!(@organization_id, @mission_id,
        revision_label: "Next revision",
        yaml: """
        packets:
          - name: REPLACEMENT
            apid: 42
            items:
              - name: new_mode
                data_type: uint
                bit_offset: 0
                bit_size: 16
        commands: []
        """
      )

    configure(c, other)
    changed = read(c)
    assert changed["selection"]["unavailable_ids"] == input["selected_packet_ids"]

    assert {:error, %ActionFailure{code: "review_conflict"}} =
             dispatch(c, Map.put(input, "expected_review", changed["review_token"]))

    assert {:ok, [unchanged]} =
             PacketBindings.list(c.scope, c.host, c.installation.application_installation_id)

    assert unchanged.configuration_version == 1
  end

  defp configure(c, revision \\ nil, apids \\ [42]) do
    revision = revision || c.revision

    assert {:ok, _} =
             TelemetryDecom.configure(@organization_id, @mission_id, c.spacecraft.spacecraft_id,
               catalog_revision_id: revision.catalog_revision_id,
               source_endpoint_id: c.endpoint.source_endpoint_id,
               handled_apids: apids
             )
  end

  defp query(params \\ %{}),
    do: %SurfaceQueryRequest{
      application_key: "telemetry_decom",
      application_version: 1,
      surface_id: "packet_bindings",
      surface_version: 1,
      query_id: "cadence.packet_bindings.manage",
      query_version: 1,
      params: params
    }

  defp read(c, params \\ %{}) do
    assert {:ok, %{"data" => page}} = PacketSurface.load(c.scope, c.host, query(params))
    page
  end

  defp dispatch(c, input),
    do:
      ActionDispatcher.dispatch(c.scope, c.host, %ActionRequest{
        application_key: "telemetry_decom",
        application_version: 1,
        surface_id: "packet_bindings",
        surface_version: 1,
        action_id: "save_packet_bindings",
        params: input
      })

  defp client_input(page) do
    root = Path.expand("../../../../../../frontend", __DIR__)

    script =
      Path.join(root, "modules/telemetry-decom/src/features/packet-bindings/producer-check.mjs")

    {output, status} = System.cmd("node", [script, Jason.encode!(page)], stderr_to_stdout: true)
    assert status == 0, output
    [_, input] = Regex.run(~r/CADENCE_PACKET_INPUT=([^\n]+)/, output)
    Jason.decode!(input)
  end

  defp export_fixture(name, page) do
    if directory = System.get_env("CADENCE_PACKET_FIXTURES") do
      File.mkdir_p!(directory)
      File.write!(Path.join(directory, name <> ".json"), Jason.encode!(%{page: page}))
    end
  end

  defp large_catalog do
    packets =
      Enum.map_join(0..529, "\n", fn index ->
        fields =
          Enum.map_join(0..if(index == 0, do: 59, else: 0), "\n", fn field ->
            "      - name: field_#{field}\n        data_type: uint\n        bit_offset: #{field * 8}\n        bit_size: 8"
          end)

        "  - name: PACKET_#{index}\n    apid: #{index}\n    items:\n#{fields}"
      end)

    "packets:\n#{packets}\ncommands: []\n"
  end
end
