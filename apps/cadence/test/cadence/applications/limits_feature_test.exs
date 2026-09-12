defmodule Cadence.Applications.LimitsFeatureTest do
  use Cadence.DataCase, async: false

  alias Cadence.Applications.{
    ActionDispatcher,
    ActionRequest,
    ApplicationInstallations,
    HostContext,
    SurfaceQueryRequest
  }

  alias Cadence.Applications.TelemetryDecomFixtures
  alias Cadence.Auth.Scope
  alias Cadence.Limits
  alias Cadence.Limits.{Definition, DefinitionLifecycle, Store}
  alias Cadence.Reads.ApplicationSurfaces.Limits, as: Surface
  @org "org-limits-feature"
  @mission "mission-limits-feature"
  setup do
    persist_mission_scope(@org, @mission)

    scope = %Scope{
      actor_kind: :user,
      organization_id: @org,
      user: %{user_id: "limits-editor"},
      organization_membership: %{lifecycle_state: :active}
    }

    host = HostContext.mission(@mission)
    {:ok, installation} = ApplicationInstallations.install(scope, host, "limits")
    %{scope: scope, host: host, installation: installation}
  end

  test "real producer reaches the public editor and saves the exact reviewed activation", c do
    doc = read(c, "manage", %{"point" => "HK.voltage", "set" => "FLIGHT"})
    export("new", doc)

    assert doc["editor"]["review"] == %{
             "definition_id" => nil,
             "version" => 0,
             "activation_event_id" => nil
           }

    {out, status} = probe(doc)
    assert status == 0, out
    [_, encoded] = Regex.run(~r/CADENCE_LIMITS_INPUT=([^\n]+)/, out)
    input = Jason.decode!(encoded)
    assert {:ok, saved} = ActionDispatcher.dispatch(c.scope, c.host, request(input))
    assert saved.version == 1
    assert saved.thresholds == %{"yellow_high" => 31.5, "red_high" => 34.0}
    assert [active] = DefinitionLifecycle.list_active_statuses(@org, @mission)
    assert active.limit_definition_id == saved.limit_definition_id
    selected = read(c, "manage", %{"definition" => saved.limit_definition_id})

    assert selected["editor"]["review"]["activation_event_id"] ==
             active.limit_definition_lifecycle_event_id

    export("selected", selected)

    assert {:error, %Cadence.Applications.ActionFailure{code: "review_conflict"}} =
             ActionDispatcher.dispatch(c.scope, c.host, request(input))
  end

  test "definition, immutable history, activation history and point pages retain complete counts",
       c do
    for i <- 1..27 do
      assert {:ok, _} =
               Limits.persist_limit_definition(definition("definition-#{i}", "HK.point#{i}", 1),
                 publish_facts?: false
               )

      assert {:ok, _} =
               Cadence.Governance.persist_derived_definition(
                 Cadence.DerivedTelemetry.Definition.new(%{
                   mission_id: @mission,
                   derived_definition_id: "derived-#{i}",
                   point_id: "DERIVED.point#{i}",
                   expression: "HK.point#{i} * 2"
                 })
               )
    end

    for v <- 2..27,
        do:
          assert(
            {:ok, _} =
              Limits.persist_limit_definition(definition("definition-1", "HK.point1", v),
                publish_facts?: false
              )
          )

    directory = read(c, "manage", %{"page" => "2", "points_page" => "2"})
    assert directory["definitions"]["total_count"] == 27
    assert length(directory["definitions"]["items"]) == 2
    assert directory["points"]["total_count"] == 27
    assert length(directory["points"]["items"]) == 2

    history =
      read(c, "manage", %{
        "definition" => "definition-1",
        "version" => "1",
        "history_page" => "2",
        "activation_page" => "2"
      })

    assert history["selection"]["inspected"]["version"] == 1
    assert history["selection"]["current"]["version"] == 27
    assert history["selection"]["history"]["total_count"] == 27
    assert length(history["selection"]["history"]["items"]) == 2
    assert history["selection"]["activations"]["total_count"] == 27
    assert length(history["selection"]["activations"]["items"]) == 2

    assert read(c, "manage", %{"definition" => "definition-1", "version" => "999"})["selection"][
             "available"
           ] == false

    export("directory-last", directory)
    export("history", history)
  end

  test "posture pages retain scope, severity counts, exact samples and old producing versions",
       c do
    assert {:ok, _} =
             Limits.persist_limit_definition(definition("voltage", "HK.voltage", 1),
               publish_facts?: false
             )

    crafts =
      Enum.map(1..27, fn i ->
        TelemetryDecomFixtures.persist_spacecraft!(@org, @mission, display_name: "Vehicle #{i}")
      end)

    for {craft, i} <- Enum.with_index([nil | crafts], 1) do
      source = %{
        mission_id: @mission,
        spacecraft_id: craft && craft.spacecraft_id,
        point_id: "HK.voltage",
        point_name: "Voltage",
        source_sample_type: :telemetry_sample,
        sample_id: "sample-#{i}",
        value: 40,
        generation_time: nil,
        receipt_time: ~U[2026-09-08 12:00:00Z],
        provenance: %{}
      }

      active = DefinitionLifecycle.list_active_definitions(@org, @mission, [])
      assert {:ok, [event]} = Limits.evaluate_source_samples([source], active)
      assert {:ok, [_]} = Store.persist_latest_states(Cadence.Repo, [event])
    end

    assert {:ok, _} =
             Limits.persist_limit_definition(definition("voltage", "HK.voltage", 2),
               publish_facts?: false
             )

    first = read(c, "activity")
    assert first["states"]["total_count"] == 28
    assert first["counts"]["red"] == 28
    assert length(first["states"]["items"]) == 25
    last = read(c, "activity", %{"page" => "2", "spacecraft_page" => "2"})
    assert length(last["states"]["items"]) == 3
    assert last["spacecraft"]["total_count"] == 27
    assert length(last["spacecraft"]["items"]) == 2
    mission = read(c, "activity", %{"spacecraft" => "mission"})
    assert mission["states"]["total_count"] == 1

    assert [%{"spacecraft_id" => nil, "definition_version" => 1, "sample_id" => "sample-1"}] =
             mission["states"]["items"]

    exact =
      read(c, "activity", %{
        "limit_definition_id" => "voltage",
        "limit_definition_version" => "1",
        "point_id" => "HK.voltage"
      })

    assert exact["selection"]["inspected"]["version"] == 1
    assert exact["selection"]["current"]["version"] == 2
    {out, status} = probe(exact, "activity")
    assert status == 0, out
    assert out =~ "CADENCE_LIMITS_POSTURE_OK"
    export("posture", first)
    export("posture-last", last)
    export("posture-mission", mission)
    export("posture-historical", exact)
  end

  test "unsupported scopes, contradictory aliases, and disabled installation fail closed", c do
    assert {:error, :invalid_application_surface_query} =
             Surface.load(
               c.scope,
               c.host,
               query("activity", %{"definition" => "one", "limit_definition_id" => "two"})
             )

    assert {:error, :mission_not_found} =
             Surface.load(%{c.scope | organization_id: "other-org"}, c.host, query("manage", %{}))

    assert {:error, :unsupported_application_surface_query} =
             Surface.load(c.scope, HostContext.organization(@org), query("manage", %{}))

    assert {:ok, _} = ApplicationInstallations.disable(c.scope, c.host, "limits")

    assert {:error, :application_installation_disabled} =
             Surface.load(c.scope, c.host, query("manage", %{}))
  end

  defp definition(id, point, v),
    do:
      Definition.new(%{
        mission_id: @mission,
        limit_definition_id: id,
        point_id: point,
        version: v,
        limit_set_name: "FLIGHT",
        thresholds: %{"yellow_high" => 20, "red_high" => 30}
      })

  defp request(input),
    do: %ActionRequest{
      application_key: "limits",
      application_version: 1,
      surface_id: "manage",
      surface_version: 1,
      action_id: "save_limit_definition",
      params: input
    }

  defp query(surface, params),
    do: %SurfaceQueryRequest{
      application_key: "limits",
      application_version: 1,
      surface_id: surface,
      surface_version: 1,
      query_id: "cadence.limits.#{surface}",
      query_version: 1,
      params: params
    }

  defp read(c, surface, params \\ %{}) do
    assert {:ok, %{"data" => doc}} = Surface.load(c.scope, c.host, query(surface, params))
    doc
  end

  defp probe(doc, surface \\ "manage") do
    script =
      Path.expand(
        "../../../../../frontend/modules/limits-and-alarming/src/features/definitions/producer-consumer-probe.mjs",
        __DIR__
      )

    System.cmd("node", [script, Jason.encode!(doc), surface], stderr_to_stdout: true)
  end

  defp export(name, doc) do
    if dir = System.get_env("CADENCE_LIMITS_FIXTURES") do
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, name <> ".json"), Jason.encode!(doc))
    end
  end
end
