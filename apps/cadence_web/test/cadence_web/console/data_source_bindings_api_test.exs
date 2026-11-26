defmodule CadenceWeb.Console.DataSourceBindingsAPITest do
  @moduledoc """
  DECISIONS #90 / ux U53: a platform-wide binding's switch, blast radius and history, and a
  mission's binding list (docs/apogee/api/setup.md §Data sources).
  """
  use CadenceWeb.ConnCase, async: false

  @moduletag :capture_log

  alias Cadence.Administration.{PlatformAudit, PlatformEvents}
  alias Cadence.DataSources.{DataBinding, DataSource}
  alias Cadence.Management.DataSources
  alias CadenceWeb.TestFixtures

  setup do
    n = System.unique_integer([:positive])

    admin =
      TestFixtures.persist_user!(display_name: "Pat Platform", capabilities: [:platform_admin])

    org = TestFixtures.persist_org!()
    member = TestFixtures.persist_user!(display_name: "Mira K.")
    TestFixtures.grant_membership!(member, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org)

    from = platform_source!("managed_store_#{n}", "Cadence managed store")
    to = platform_source!("archive_store_#{n}", "Northlight archive")

    {:ok, binding} =
      DataSources.persist_data_binding(%DataBinding{
        binding_id: "platform_telemetry_#{n}",
        organization_id: nil,
        mission_id: nil,
        realm: "flight",
        logical_source: :telemetry,
        data_source_id: from.data_source_id
      })

    %{
      admin: admin,
      member: member,
      org: org,
      mission: mission,
      binding: binding,
      to: to,
      base: "/api/console/v1/missions/#{mission.mission_id}"
    }
  end

  test "the mission's list marks a platform binding it falls back to as shared", c do
    assert %{"data" => %{"bindings" => bindings}} =
             c.member
             |> TestFixtures.member_conn()
             |> get(c.base <> "/data-source-bindings")
             |> json_response(200)

    assert %{
             "shared" => true,
             "logical_source" => "telemetry",
             "data_source" => %{"display_name" => "Cadence managed store"}
           } = Enum.find(bindings, &(&1["id"] == c.binding.binding_id))
  end

  test "blast radius: platform admins in admin mode only, even without membership", c do
    path = c.base <> "/data-source-bindings/#{c.binding.binding_id}/blast-radius"

    assert %{"error" => %{"code" => "platform_source"}} =
             c.member |> TestFixtures.member_conn() |> get(path) |> json_response(403)

    assert %{
             "data" => %{
               "affected_missions" => missions,
               "live_passes" => %{"total" => 0, "first" => []},
               "binding" => %{"id" => id, "from" => %{"display_name" => "Cadence managed store"}}
             }
           } = c |> admin_conn() |> get(path) |> json_response(200)

    assert id == c.binding.binding_id
    assert missions >= 1
  end

  test "a shared switch needs a reason and the shown counts, and is audited twice", c do
    path = c.base <> "/data-source-bindings/#{c.binding.binding_id}"
    conn = admin_conn(c)

    %{"data" => %{"affected_missions" => missions}} =
      conn |> get(path <> "/blast-radius") |> json_response(200)

    body = %{
      "data_source_id" => c.to.data_source_id,
      "expected_data_source_id" => c.binding.data_source_id,
      "expected_affected_missions" => missions,
      "expected_live_passes_total" => 0
    }

    assert %{"error" => %{"code" => "invalid_params", "details" => %{"field" => "reason"}}} =
             conn |> put(path, body) |> json_response(422)

    assert %{
             "error" => %{
               "code" => "blast_radius_changed",
               "details" => %{"affected_missions" => ^missions, "binding" => %{"id" => _}}
             }
           } =
             conn
             |> put(
               path,
               Map.merge(body, %{"reason" => "Move", "expected_affected_missions" => missions + 7})
             )
             |> json_response(409)

    assert %{
             "data" => %{
               "binding" => %{"data_source_id" => to_id, "shared" => true},
               "recorded" => %{"affected_missions" => ^missions, "live_passes_total" => 0}
             }
           } =
             conn
             |> put(path, Map.put(body, "reason", "Northlight takes the archive."))
             |> json_response(200)

    assert to_id == c.to.data_source_id

    assert %{"data" => %{"events" => [switch | _]}} =
             conn |> get(path <> "/events") |> json_response(200)

    assert %{
             "kind" => "switched",
             "reason" => "Northlight takes the archive.",
             "affected_missions" => ^missions,
             "to" => %{"display_name" => "Northlight archive"}
           } = switch

    assert [%{action: "platform_binding_switched", details: details}] =
             PlatformEvents.list(limit: 5) |> Enum.filter(&(&1.target_id == c.binding.binding_id))

    assert details["reason"] == "Northlight takes the archive."

    # Admin › Audit (ux U53's line).
    assert [%{action: line}] =
             PlatformEvents.list(limit: 5)
             |> Enum.filter(&(&1.target_id == c.binding.binding_id))
             |> PlatformAudit.events()

    assert line ==
             "Switched platform binding #{c.binding.binding_id} from Cadence managed store to " <>
               "Northlight archive · #{missions} mission#{if missions == 1, do: "", else: "s"}, " <>
               "0 live passes: “Northlight takes the archive.”"
  end

  # api-ops' sweep (11-15): a platform-wide binding serves every tenant that falls back to it, so
  # pointing it at one organization's own source would send everyone's data there.
  test "a platform-wide binding refuses an organization's own source as its target", c do
    {:ok, own} =
      DataSources.persist_data_source(%DataSource{
        data_source_id: "org_own_store_#{System.unique_integer([:positive])}",
        owner: :cadence,
        kind: :managed_tsdb,
        adapter: Cadence.Dashboards.Sources.Telemetry,
        organization_id: c.org.organization_id,
        mission_id: c.mission.mission_id,
        isolation_level: :mission_isolated,
        capabilities: %{latest?: true},
        metadata: %{storage: :questdb, display_name: "Our own store"}
      })

    path = c.base <> "/data-source-bindings/#{c.binding.binding_id}"
    conn = admin_conn(c)

    %{"data" => %{"affected_missions" => missions}} =
      conn |> get(path <> "/blast-radius") |> json_response(200)

    assert %{
             "error" => %{
               "code" => "platform_target_required",
               "details" => %{"field" => "data_source_id"}
             }
           } =
             conn
             |> put(path, %{
               "data_source_id" => own.data_source_id,
               "expected_data_source_id" => c.binding.data_source_id,
               "reason" => "Use ours.",
               "expected_affected_missions" => missions,
               "expected_live_passes_total" => 0
             })
             |> json_response(422)

    assert {:ok, %DataBinding{data_source_id: unchanged}} =
             DataSources.fetch_data_binding(c.binding.binding_id)

    assert unchanged == c.binding.data_source_id

    assert [] =
             PlatformEvents.list(limit: 5) |> Enum.filter(&(&1.target_id == c.binding.binding_id))
  end

  test "outside admin mode, a platform binding's history hides the admin, the reason and the counts",
       c do
    path = c.base <> "/data-source-bindings/#{c.binding.binding_id}"
    conn = admin_conn(c)

    %{"data" => %{"affected_missions" => missions}} =
      conn |> get(path <> "/blast-radius") |> json_response(200)

    conn
    |> put(path, %{
      "data_source_id" => c.to.data_source_id,
      "expected_data_source_id" => c.binding.data_source_id,
      "reason" => "Northlight takes the archive.",
      "expected_affected_missions" => missions,
      "expected_live_passes_total" => 0
    })
    |> json_response(200)

    assert %{"data" => %{"events" => [switch | _]}} =
             c.member
             |> TestFixtures.member_conn()
             |> get(path <> "/events")
             |> json_response(200)

    assert %{
             "kind" => "switched",
             "to" => %{"display_name" => "Northlight archive"},
             "actor" => nil,
             "reason" => nil,
             "affected_missions" => nil,
             "live_passes_total" => nil
           } = switch

    assert %{"data" => %{"events" => [%{"reason" => "Northlight takes the archive."} | _]}} =
             conn |> get(path <> "/events") |> json_response(200)
  end

  # qa (11-15): a registered or changed event's from/to had a null display_name, which the
  # console's reader rightly refuses.
  test "every history entry names its sources, not only a switch's", c do
    path = c.base <> "/data-source-bindings/#{c.binding.binding_id}/events"

    assert %{"data" => %{"events" => [_ | _] = events}} =
             c.member |> TestFixtures.member_conn() |> get(path) |> json_response(200)

    refs = Enum.flat_map(events, &[&1["from"], &1["to"]]) |> Enum.reject(&is_nil/1)
    assert refs != []
    assert Enum.all?(refs, &is_binary(&1["display_name"]))
    assert %{"display_name" => "Cadence managed store"} = List.last(events)["to"]
  end

  # #471 (#146's rule): on an organization's own binding, a member is named; someone outside the
  # organization (a platform admin acting as support) is recorded but neither named nor
  # identified, and nobody's email is sent.
  test "an organization's binding history names members only, never by email", c do
    n = System.unique_integer([:positive])

    {:ok, own} =
      DataSources.persist_data_binding(
        %DataBinding{
          binding_id: "org_telemetry_#{n}",
          organization_id: c.org.organization_id,
          mission_id: c.mission.mission_id,
          realm: "flight",
          logical_source: :telemetry,
          data_source_id: c.binding.data_source_id
        },
        actor_id: c.member.user_id
      )

    {:ok, _changed} =
      DataSources.persist_data_binding(%{own | data_source_id: c.to.data_source_id},
        actor_id: c.admin.user_id
      )

    body =
      c.member
      |> TestFixtures.member_conn()
      |> get(c.base <> "/data-source-bindings/#{own.binding_id}/events")
      |> json_response(200)

    assert %{"data" => %{"events" => [changed, registered]}} = body
    assert changed["actor"] == %{"id" => nil, "name" => nil}
    assert registered["actor"] == %{"id" => c.member.user_id, "name" => "Mira K."}

    encoded = Jason.encode!(body)
    refute encoded =~ c.admin.email
    refute encoded =~ c.admin.user_id
    refute encoded =~ c.member.email
  end

  defp admin_conn(c) do
    c.admin
    |> TestFixtures.member_conn()
    |> Plug.Test.init_test_session(%{admin_mode_expires_at: System.system_time(:second) + 600})
  end

  defp platform_source!(id, name) do
    {:ok, source} =
      DataSources.persist_data_source(%DataSource{
        data_source_id: id,
        owner: :cadence,
        kind: :managed_tsdb,
        adapter: Cadence.Dashboards.Sources.Telemetry,
        isolation_level: :shared,
        capabilities: %{latest?: true},
        metadata: %{storage: :questdb, display_name: name}
      })

    source
  end
end
