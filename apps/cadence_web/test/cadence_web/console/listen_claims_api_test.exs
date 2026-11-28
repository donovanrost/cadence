defmodule CadenceWeb.Console.ListenClaimsAPITest do
  @moduledoc """
  A listen host:port belongs to one mission (the port is a node resource): the console's change-set
  preview refuses another mission's transport on it with the field error at configuration.port,
  without naming the other mission, which may be another organization's. The same mission reusing
  its own port passes.
  """
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Comms.{Transport, TransportStore}
  alias CadenceWeb.TestFixtures

  @message "Another mission already listens on this host and port. Choose a different port."

  setup do
    previous = Application.get_env(:cadence, :activation_governance, [])
    Application.put_env(:cadence, :activation_governance, approval_required: false)
    on_exit(fn -> Application.put_env(:cadence, :activation_governance, previous) end)

    port = 40_000 + rem(System.unique_integer([:positive]), 20_000)

    # Mission A (one organization) already listens on 127.0.0.1:port.
    org_a = TestFixtures.persist_org!()
    mission_a = TestFixtures.persist_mission!(org_a)

    {:ok, _claimed} =
      TransportStore.persist_transport(
        org_a.organization_id,
        Transport.new(%{
          mission_id: mission_a.mission_id,
          display_name: "Mission A listener",
          transport_kind: :tcp_socket,
          direction_capability: :inbound,
          adapter_key: :tcp_socket,
          configuration: listen(port)
        })
      )

    # Mission B, another organization, stages the same host and port.
    org_b = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org_b)
    mission_b = TestFixtures.persist_mission!(org_b)

    %{
      port: port,
      user: user,
      mission_a: mission_a,
      base_b: "/api/v1/missions/#{mission_b.mission_id}/config"
    }
  end

  defp listen(port),
    do: %{
      "mode" => "listen",
      "expected_peer_addresses" => ["127.0.0.1/32", "::1/128"],
      "direction_capability" => "inbound",
      "host" => "127.0.0.1",
      "port" => Integer.to_string(port),
      "framing_mode" => "raw",
      "tls_enabled" => "false"
    }

  defp transport_op(port),
    do: %{
      "kind" => "transport",
      "action" => "create",
      "document" => %{"display_name" => "Mission B listener", "configuration" => listen(port)}
    }

  defp post_json(c, path, body, status),
    do:
      c.user
      |> TestFixtures.member_conn()
      |> post(c.base_b <> path, body)
      |> json_response(status)
      |> Map.fetch!("data")

  defp port_errors(preview) do
    validation = Enum.find(preview["checks"], &(&1["key"] == "validation"))
    for item <- validation["items"], error <- item["errors"], do: error
  end

  test "another mission's port is refused in preview, on configuration.port, unnamed", c do
    preview = post_json(c, "/preview", %{"ops" => [transport_op(c.port)]}, 200)

    assert preview["verdict"] == "no_go"
    assert [%{"path" => "configuration.port", "message" => @message}] = port_errors(preview)
    refute Jason.encode!(preview) =~ c.mission_a.mission_id
  end

  test "a staged change set shows the same refusal in its preview", c do
    staged = post_json(c, "/stage", %{"summary" => "Add", "ops" => [transport_op(c.port)]}, 201)
    preview = post_json(c, "/change-sets/#{staged["change_set_id"]}/preview", %{}, 200)

    assert preview["verdict"] == "no_go"
    assert [%{"path" => "configuration.port", "message" => @message}] = port_errors(preview)
  end

  test "a port nobody listens on passes", c do
    preview = post_json(c, "/preview", %{"ops" => [transport_op(c.port + 1)]}, 200)
    assert preview["verdict"] == "go"
  end
end
