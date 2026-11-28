defmodule CadenceWeb.Console.TransportListenerAPITest do
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Comms.TransportStore
  alias Cadence.Contacts.ProfileStore
  alias Cadence.ReadyProviderFixtures
  alias CadenceWeb.TestFixtures

  @listener "configuration.listener"
  @own "Own listener for each pass"
  @shared "Shared, routed by SCID"

  setup do
    org = TestFixtures.persist_org!()
    author = TestFixtures.persist_user!()
    reviewer = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(author, org)
    TestFixtures.grant_membership!(reviewer, org)
    mission = TestFixtures.persist_mission!(org)
    previous = Application.get_env(:cadence, :activation_governance, [])
    Application.put_env(:cadence, :activation_governance, approval_required: true)
    on_exit(fn -> Application.put_env(:cadence, :activation_governance, previous) end)

    %{
      org: org.organization_id,
      mission: mission.mission_id,
      author: author,
      reviewer: reviewer,
      port: 40_000 + rem(System.unique_integer([:positive]), 20_000),
      base: "/api/v1/missions/#{mission.mission_id}/config"
    }
  end

  test "schema offers listener options for listening downlinks with an Own default", c do
    schema =
      c.author
      |> TestFixtures.member_conn()
      |> get(c.base <> "/kinds/transport/schema")
      |> json_response(200)

    assert %{
             "type" => "enum",
             "label" => "Listener",
             "default" => "own",
             "enum" => [
               %{"value" => "own", "label" => @own},
               %{"value" => "shared", "label" => @shared}
             ],
             "visible_when" => %{
               "all" => [
                 %{"path" => "configuration.mode", "equals" => "listen"},
                 %{"path" => "configuration.direction_capability", "equals" => "inbound"}
               ]
             }
           } = Enum.find(schema["data"]["fields"], &(&1["path"] == @listener))
  end

  test "Own to Shared and reset preview the option words and apply reviewed transport versions",
       c do
    created = stage!(c, [create(c.port)])
    assert [id] = created["entity_ids"]
    approve!(c, created)
    assert {:ok, original} = TransportStore.fetch_transport(c.org, c.mission, id)
    refute Map.has_key?(original.configuration, "listener")

    shared = stage!(c, [update(id, [change(@listener, "shared")])])

    assert %{
             "before" => nil,
             "after" => "shared",
             "before_label" => @own,
             "after_label" => @shared
           } =
             preview_listener(c, shared)

    approve!(c, shared)
    assert {:ok, shared_version} = TransportStore.fetch_transport(c.org, c.mission, id)

    assert {:ok, profile} =
             ProfileStore.fetch_provider_profile(
               c.org,
               c.mission,
               shared_version.materialized_provider_profile_id
             )

    assert profile.configuration["listener"] == "shared"

    connect = change("configuration.mode", "connect")

    refused = stage(c, [update(id, [connect])], 422)

    assert [%{"path" => @listener, "code" => "shared_listener_requires_downlink"}] =
             refused["error"]["details"]["errors"]

    reset = stage!(c, [update(id, [connect, change(@listener, "own")])])

    assert %{
             "before_label" => @shared,
             "after_label" => @own,
             "note" => "Only a downlink transport that listens can share one."
           } = preview_listener(c, reset)

    approve!(c, reset)
    assert {:ok, own_version} = TransportStore.fetch_transport(c.org, c.mission, id)
    assert own_version.configuration["listener"] == "own"
    assert own_version.configuration["mode"] == "connect"
  end

  test "stage refuses an invalid choice and two new plaintext bindings on the same port", c do
    invalid = stage(c, [create(c.port, "sometimes")], 422)

    assert [%{"path" => @listener, "code" => "invalid_listener_choice"}] =
             invalid["error"]["details"]["errors"]

    spoofed =
      put_in(create(c.port, "shared"), ["document", "configuration", "delivery_auth"], "mtls")

    refused = stage(c, [spoofed], 422)

    assert [%{"path" => @listener, "code" => "shared_listener_unavailable_mtls"}] =
             refused["error"]["details"]["errors"]

    refused = stage(c, [create(c.port, "shared"), create(c.port, "shared")], 422)

    assert %{
             "index" => 1,
             "errors" => [
               %{
                 "path" => @listener,
                 "code" => "shared_listener_requires_mtls",
                 "message" => "Sharing across provider bindings needs mutual TLS."
               }
             ]
           } = refused["error"]["details"]

    stage!(c, [create(c.port, "shared")])
    refused = stage(c, [create(c.port, "shared")], 422)

    assert [%{"path" => @listener, "code" => "shared_listener_requires_mtls"}] =
             refused["error"]["details"]["errors"]
  end

  test "provider-managed transport choice reaches its profile while provider settings remain derived",
       c do
    provider = ReadyProviderFixtures.persist_ready_provider!(c.org, c.mission)

    op = %{
      "kind" => "transport",
      "action" => "create",
      "document" => %{
        "display_name" => "Provider downlink",
        "origin" => "provider_managed",
        "mission_provider_id" => provider.provider_id,
        "mission_provider_version" => provider.version,
        "service_profile_ref" => %{"id" => "service-downlink", "version" => 3},
        "delivery_profile_ref" => %{"id" => "delivery-cadence", "version" => 7},
        "configuration" => %{"listener" => "shared", "port" => 1, "delivery_auth" => "mtls"}
      }
    }

    staged = stage!(c, [op])
    assert [id] = staged["entity_ids"]
    assert %{"after_label" => @shared} = preview_listener(c, staged)

    approve!(c, staged)
    assert {:ok, transport} = TransportStore.fetch_transport(c.org, c.mission, id)

    assert {:ok, profile} =
             ProfileStore.fetch_provider_profile(
               c.org,
               c.mission,
               transport.materialized_provider_profile_id
             )

    assert %{"listener" => "shared", "port" => 5100, "expected_peer_addresses" => [_ | _]} =
             profile.configuration

    refute Map.has_key?(profile.configuration, "delivery_auth")
  end

  defp create(port, listener \\ nil) do
    config = %{
      "mode" => "listen",
      "direction_capability" => "inbound",
      "host" => "127.0.0.1",
      "port" => port,
      "framing_mode" => "fixed_size",
      "frame_size" => 64,
      "expected_peer_addresses" => ["127.0.0.1/32"]
    }

    config = if listener, do: Map.put(config, "listener", listener), else: config

    %{
      "kind" => "transport",
      "action" => "create",
      "document" => %{"display_name" => "Downlink", "configuration" => config}
    }
  end

  defp update(id, changes),
    do: %{"kind" => "transport", "action" => "update", "entity_id" => id, "changes" => changes}

  defp change(path, value), do: %{"path" => path, "value" => value}

  defp stage!(c, ops), do: stage(c, ops, 201)["data"]

  defp stage(c, ops, status),
    do:
      request(
        c.author,
        c.base <> "/stage",
        %{"summary" => "Set up downlink", "ops" => ops},
        status
      )

  defp preview_listener(c, staged) do
    preview = request(c.author, set_path(c, staged) <> "/preview", %{}, 200)["data"]
    assert preview["verdict"] == "go"
    assert [diff] = preview["diffs"]
    Enum.find(diff["fields"], &(&1["path"] == @listener))
  end

  defp approve!(c, staged) do
    path = set_path(c, staged)

    assert %{"state" => "in_review", "version" => version} =
             request(
               c.author,
               path <> "/submit",
               %{
                 "reason" => "Review the downlink transport settings",
                 "expected_version" => staged["version"]
               },
               200
             )["data"]

    assert %{"state" => "applied"} =
             request(
               c.reviewer,
               path <> "/review",
               %{
                 "decision" => "approve",
                 "expected_version" => version
               },
               200
             )["data"]
  end

  defp set_path(c, staged), do: c.base <> "/change-sets/" <> staged["change_set_id"]

  defp request(user, path, body, status),
    do: user |> TestFixtures.member_conn() |> post(path, body) |> json_response(status)
end
