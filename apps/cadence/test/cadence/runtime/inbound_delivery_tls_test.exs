defmodule Cadence.Runtime.InboundDeliveryTLSTest do
  use Cadence.RuntimeCase, async: false

  import Cadence.ReadyProviderFixtures

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Auth.Scope
  alias Cadence.Comms.{ProviderDeliveryListenerRead, Transport}
  alias Cadence.Contacts.ProfileStore
  alias Cadence.DeliveryCredentialFixtures
  alias Cadence.GroundNetworks.{MissionProviders, ProviderAccountGrants, ProviderAccounts}
  alias Cadence.GroundNetworks.ProviderCredentials
  alias Cadence.GroundNetworks.ProviderDeliveryCredentials
  alias Cadence.IngressJournal.FileSystem, as: Journal
  alias Cadence.Management.Transports
  alias Cadence.ProviderAdapters.InboundSocket.Authorization
  alias Cadence.ProviderAdapters.TCPSocket
  alias Cadence.ProviderAdapters.TCPSocket.Configuration
  alias Cadence.Runtime.Contacts
  alias Cadence.Runtime.{ProcessNamespace, ProfileAcceptor, ProviderIngressExecutor}
  alias Cadence.Secrets.DevelopmentDeliveryTLS
  alias Cadence.SharedListenerFixtures

  @service_ref %{"id" => "service-downlink", "version" => 3}
  @plaintext_ref %{"id" => "delivery-cadence", "version" => 7}
  @mtls_ref %{"id" => "delivery-cadence", "version" => 8}

  setup do
    material = DevelopmentDeliveryTLS.generate()
    previous = Application.fetch_env(:cadence, :provider_delivery_listener)

    Application.put_env(:cadence, :provider_delivery_listener,
      secret_reference: "test-delivery-server",
      secret_backend: fn %{purpose: "provider_delivery_listener"} ->
        {:ok,
         %{
           material: %{
             certificate_pem: material.server_certificate_pem,
             private_key_pem: material.server_key_pem,
             client_ca_pem: material.client_ca_pem
           }
         }}
      end
    )

    on_exit(fn ->
      case previous do
        {:ok, opts} -> Application.put_env(:cadence, :provider_delivery_listener, opts)
        :error -> Application.delete_env(:cadence, :provider_delivery_listener)
      end
    end)

    %{material: material}
  end

  test "the own listener authenticates before reading and records the client generation", %{
    material: material
  } do
    ctx = issue_binding!(material)
    other_binding = issue_binding!(material)
    transport = enable_tls!(ctx)
    {adapter, journal, port} = start_listener!(ctx, transport)
    assert_rejected(connect(port, material))
    assert_rejected(connect(port, material, other_binding.client))
    assert eventually(fn -> reason(adapter) == "unknown_leaf" end)
    assert :empty = Journal.next_entries(journal, :processing, 10, 16_384)

    {:ok, stalled} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false])
    {:ok, peer} = connect(port, material, ctx.client)
    :gen_tcp.close(stalled)
    bytes = SharedListenerFixtures.frame(7)
    :ok = :ssl.send(peer, bytes)
    assert eventually(fn -> received?(adapter) end)

    assert {:ok, [entry]} = Journal.next_entries(journal, :processing, 10, 16_384)
    binding = transport.transport_id
    fingerprint = ctx.client.fingerprint

    assert %{
             "provider_binding_id" => ^binding,
             "client_certificate_fingerprint" => ^fingerprint,
             "client_certificate_generation" => 1
           } = entry.metadata.ingress_metadata["delivery_authentication"]

    assert {:ok, _} =
             ProviderDeliveryCredentials.revoke(
               ctx.scope,
               ctx.mission,
               ctx.provider.provider_id,
               binding,
               %{
                 "fingerprint" => fingerprint,
                 "reason" => "suspected_compromise"
               }
             )

    send(adapter, {:provider_delivery_credentials_changed, ctx.org, ctx.mission})
    assert {:error, :closed} = :ssl.recv(peer, 0, 2_000)
    assert eventually(fn -> reason(adapter) == "revoked" end)
  end

  test "a verified shared peer hands its first frame and certificate identity to its adapter", %{
    material: material
  } do
    ctx = issue_binding!(material, "shared")
    {adapter, journal, port} = start_listener!(ctx, enable_tls!(ctx))
    {:ok, peer} = connect(port, material, ctx.client)
    :ok = :ssl.send(peer, SharedListenerFixtures.frame(7))
    assert eventually(fn -> received?(adapter) end)

    assert {:ok, [entry]} = Journal.next_entries(journal, :processing, 10, 16_384)

    assert entry.metadata.ingress_metadata["delivery_authentication"][
             "client_certificate_fingerprint"
           ] ==
             ctx.client.fingerprint
  end

  test "the shared acceptor rejects mixed mode and applies its registration allowlist after TLS",
       %{material: material} do
    ctx = issue_binding!(material, "shared", ["10.0.0.0/8"])
    transport = enable_tls!(ctx)
    {adapter, journal, port} = start_listener!(ctx, transport)

    assert {:error, :mode_mismatch} =
             ProfileAcceptor.register(
               ProcessNamespace.default(),
               ctx.mission,
               transport.materialized_provider_profile_id,
               %{host: "127.0.0.1", port: port},
               %{adapter: self(), realized_contact_id: "other", path_id: "downlink", scid: 7}
             )

    assert {:error, {:listen_endpoint_listener_mismatch, %{port: ^port}}} =
             Transports.persist_transport(ctx.org, direct_transport(ctx.mission, port))

    {:ok, peer} = connect(port, material, ctx.client)
    assert {:error, :closed} = :ssl.recv(peer, 0, 2_000)
    assert eventually(fn -> reason(adapter) == "peer_not_allowed" end)
    assert :empty = Journal.next_entries(journal, :processing, 10, 16_384)
  end

  test "shared mTLS claims remain exclusive across organizations using the same CA and SCID", %{
    material: material
  } do
    a = issue_binding!(material, "shared")
    b = issue_binding!(material, "shared")
    assert a.org != b.org
    assert a.mission != b.mission

    first = enable_tls!(a)
    port = first.configuration["port"]

    assert {:error, {:listen_endpoint_claimed, %{port: ^port}}} = enable_tls(b, port)

    # Each organization can start a binding with the same SCID (7 in start_listener!) using
    # its CA-issued leaf on its own endpoint.
    second = enable_tls!(b)
    assert second.configuration["port"] != port

    for {ctx, other, transport} <- [{a, b, first}, {b, a, second}] do
      {adapter, journal, port} = start_listener!(ctx, transport)
      assert_rejected(connect(port, material, other.client))
      assert eventually(fn -> reason(adapter) == "unknown_leaf" end)
      assert :empty = Journal.next_entries(journal, :processing, 10, 16_384)

      {:ok, peer} = connect(port, material, ctx.client)
      :ok = :ssl.send(peer, SharedListenerFixtures.frame(7))
      assert eventually(fn -> received?(adapter) end)
      :ssl.close(peer)
    end
  end

  test "a shared mTLS endpoint routes the same SCID independently within each binding", %{
    material: material
  } do
    a = issue_binding!(material, "shared")
    b = issue_binding!(material, "own", nil, {a.org, a.mission, a.scope})
    first = enable_tls!(a)
    port = first.configuration["port"]

    assert {:error, {:listen_endpoint_listener_mismatch, %{port: ^port}}} = enable_tls(b, port)

    assert {:ok, second} = enable_tls(%{b | listener: "shared"}, port)
    assert first.transport_id != second.transport_id

    for {ctx, transport} <- [{a, first}, {b, second}] do
      assert {:ok, profile} =
               ProfileStore.fetch_provider_profile(
                 ctx.org,
                 ctx.mission,
                 transport.materialized_provider_profile_id
               )

      assert %{
               "listener" => "shared",
               "port" => ^port,
               "delivery_auth" => "mtls",
               "delivery_credential_ref" => ref
             } = profile.configuration

      assert ref == ctx.client.ref
    end

    {adapter_a, journal_a, ^port} = start_listener!(a, first)
    {adapter_b, journal_b, ^port} = start_listener!(b, second)
    assert_rejected(connect(port, material))

    assert eventually(fn ->
             rows = Contacts.listener_refusals(a.mission)

             length(rows) == 2 and
               Enum.all?(rows, &(&1.refusals_per_minute.tls_handshake_failed == 1))
           end)

    {:ok, peer_a} = connect(port, material, a.client)
    {:ok, peer_b} = connect(port, material, b.client)
    :ok = :ssl.send(peer_a, SharedListenerFixtures.frame(7))
    assert eventually(fn -> received?(adapter_a) end)
    refute received?(adapter_b)
    assert :empty = Journal.next_entries(journal_b, :processing, 10, 16_384)

    :ok = :ssl.send(peer_b, SharedListenerFixtures.frame(7))
    assert eventually(fn -> received?(adapter_b) end)

    for {ctx, transport, journal} <- [{a, first, journal_a}, {b, second, journal_b}] do
      assert {:ok, [entry]} = Journal.next_entries(journal, :processing, 10, 16_384)

      assert entry.metadata.ingress_metadata["delivery_authentication"] == %{
               "provider_binding_id" => transport.transport_id,
               "provider_profile_id" => transport.materialized_provider_profile_id,
               "client_certificate_fingerprint" => ctx.client.fingerprint,
               "client_certificate_generation" => 1
             }
    end

    assert {:ok, _} =
             ProviderDeliveryCredentials.revoke(
               a.scope,
               a.mission,
               a.provider.provider_id,
               first.transport_id,
               %{"fingerprint" => a.client.fingerprint, "reason" => "suspected_compromise"}
             )

    send(adapter_a, {:provider_delivery_credentials_changed, a.org, a.mission})
    assert {:error, :closed} = :ssl.recv(peer_a, 0, 2_000)
    {:ok, before} = TCPSocket.snapshot(adapter_b)
    :ok = :ssl.send(peer_b, SharedListenerFixtures.frame(7))

    assert eventually(fn ->
             {:ok, after_send} = TCPSocket.snapshot(adapter_b)
             after_send.downlink_bytes_received > before.downlink_bytes_received
           end)
  end

  test "an authenticated peer cannot use a SCID from another binding or an ambiguous SCID", %{
    material: material
  } do
    a = issue_binding!(material, "shared")
    b = issue_binding!(material, "shared", nil, {a.org, a.mission, a.scope})
    first = enable_tls!(a)
    port = first.configuration["port"]
    assert {:ok, second} = enable_tls(b, port)
    {adapter_a, journal_a, ^port} = start_listener!(a, first)
    {_adapter_b, journal_b, ^port} = start_listener!(b, second, 8)

    {:ok, wrong_peer} = connect(port, material, a.client)
    :ok = :ssl.send(wrong_peer, SharedListenerFixtures.frame(8))
    assert {:error, :closed} = :ssl.recv(wrong_peer, 0, 2_000)
    assert eventually(fn -> reason(adapter_a) == "unregistered_scid" end)

    {_duplicate, duplicate_journal, ^port} = start_listener!(a, first)
    {:ok, ambiguous_peer} = connect(port, material, a.client)
    :ok = :ssl.send(ambiguous_peer, SharedListenerFixtures.frame(7))
    assert {:error, :closed} = :ssl.recv(ambiguous_peer, 0, 2_000)
    assert eventually(fn -> reason(adapter_a) == "ambiguous_scid" end)

    for journal <- [journal_a, journal_b, duplicate_journal] do
      assert :empty = Journal.next_entries(journal, :processing, 10, 16_384)
    end
  end

  test "activating mTLS closes an existing plaintext stream and refuses old registrations", %{
    material: material
  } do
    ctx = issue_binding!(material)
    {adapter, _journal, port} = start_listener!(ctx, ctx.transport)
    {:ok, peer} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false])
    assert eventually(fn -> match?({:ok, %{connected?: true}}, TCPSocket.refusals(adapter)) end)

    _enabled = enable_tls!(ctx)
    send(adapter, {:configuration_changed, ctx.org, ctx.mission})

    assert {:error, :closed} = :gen_tcp.recv(peer, 0, 2_000)
    assert eventually(fn -> reason(adapter) == "mode_mismatch" end)

    assert {:error, :econnrefused} =
             :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false])
  end

  test "credential lookup refuses a different binding, an ended overlap, and an inactive grant",
       %{material: material} do
    ctx = issue_binding!(material)
    provider_id = ctx.provider.provider_id
    binding = ctx.transport.transport_id
    ref = ctx.client.ref

    assert {:error, :delivery_binding_unavailable} =
             ProviderDeliveryListenerRead.check_binding(
               ctx.org,
               ctx.mission,
               provider_id,
               "other",
               ref
             )

    assert {:error, :delivery_binding_unavailable} =
             ProviderDeliveryListenerRead.check_binding(
               ctx.org,
               ctx.mission,
               "other",
               binding,
               ref
             )

    now = DateTime.utc_now()

    refute ProviderDeliveryListenerRead.live_generation?(
             %{
               state: "previous",
               expires_at: DateTime.add(now, 1, :day),
               overlap_ends_at: now
             },
             now
           )

    assert :ok =
             ProviderDeliveryListenerRead.check_binding(
               ctx.org,
               ctx.mission,
               provider_id,
               binding,
               ref
             )

    for {table, id_column, id} <- [
          {"mission_providers", "provider_id", provider_id},
          {"provider_accounts", "provider_account_id", ctx.grant.provider_account_id}
        ] do
      Repo.query!("UPDATE #{table} SET lifecycle_state = 'archived' WHERE #{id_column} = $1", [id])

      assert {:error, :delivery_binding_unavailable} =
               ProviderDeliveryListenerRead.check_binding(
                 ctx.org,
                 ctx.mission,
                 provider_id,
                 binding,
                 ref
               )

      Repo.query!("UPDATE #{table} SET lifecycle_state = 'active' WHERE #{id_column} = $1", [id])
    end

    assert {:ok, _} =
             ProviderAccountGrants.revoke(
               ctx.scope,
               ctx.grant.provider_account_grant_id,
               "test revoke"
             )

    assert {:error, :delivery_binding_unavailable} =
             ProviderDeliveryListenerRead.check_binding(
               ctx.org,
               ctx.mission,
               provider_id,
               binding,
               ref
             )
  end

  test "materialization requires the transport's own credential and server identity", %{
    material: material
  } do
    ctx = issue_binding!(material)
    other = issue_binding!(material)

    assert {:error, :delivery_binding_unavailable} = enable_tls(%{ctx | client: other.client})

    Application.delete_env(:cadence, :provider_delivery_listener)
    assert {:error, :delivery_tls_identity_unavailable} = enable_tls(ctx)
  end

  test "a stale listener index denies a previously eligible fingerprint", %{material: material} do
    ctx = issue_binding!(material)
    transport = enable_tls!(ctx)

    {:ok, profile} =
      ProfileStore.fetch_provider_profile(
        ctx.org,
        ctx.mission,
        transport.materialized_provider_profile_id
      )

    {:ok, authorization} =
      Authorization.start(
        :mtls,
        ctx.org,
        ctx.mission,
        profile.metadata,
        Configuration.normalize(profile.configuration)
      )

    assert {:ok, _identity} = Authorization.authorize(authorization, ctx.client.fingerprint)
    [{:snapshot, _at, value}] = :ets.lookup(authorization.table, :snapshot)

    :ets.insert(
      authorization.table,
      {:snapshot, System.monotonic_time(:millisecond) - 60_000, value}
    )

    assert {:error, :stale_index} = Authorization.authorize(authorization, ctx.client.fingerprint)
  end

  defp issue_binding!(material, listener \\ nil, tls_peers \\ nil, mission_scope \\ nil) do
    {org, mission, scope} = mission_scope || new_mission_scope!()
    credential_ref = Cadence.Ids.new("provider_credential")
    account_id = Cadence.Ids.new("provider_account")

    {:ok, _credential} =
      ProviderCredentials.create(
        org,
        account_id,
        %{
          provider_credential_ref: credential_ref,
          backend_type: :external,
          backend_key: "tls-test-provider"
        },
        manage_backend?: false
      )

    {:ok, account, account_version} =
      ProviderAccounts.create(
        scope,
        %{
          provider_account_id: account_id,
          display_name: "TLS provider",
          provider_type: :simulator,
          base_url: "http://127.0.0.1:4101",
          environment_ref: "local",
          credential_ref: credential_ref
        },
        validate_credential?: false
      )

    {:ok, grant} = ProviderAccountGrants.grant(scope, mission, account.provider_account_id, %{})

    provider =
      persist_ready_provider!(org, mission, %{
        provider_account_id: account.provider_account_id,
        provider_account_version: account_version.version,
        provider_account_grant_id: grant.provider_account_grant_id,
        provider_account_grant_version: grant.version,
        credential_ref: credential_ref
      })

    port = SharedListenerFixtures.free_port()

    inventory =
      update_in(provider.inventory_sync_document, ["delivery_profiles", "items"], fn [delivery] ->
        [put_in(delivery, ["diagnostics", "port"], port)]
      end)

    {:ok, provider} =
      MissionProviders.update_operational_state(provider, %{inventory_sync_document: inventory})

    {:ok, transport} =
      Transports.persist_transport(
        org,
        Transport.new(%{
          mission_id: mission,
          display_name: "TLS delivery",
          origin: :provider_managed,
          mission_provider_id: provider.provider_id,
          mission_provider_version: provider.version,
          service_profile_ref: @service_ref,
          delivery_profile_ref: @plaintext_ref
        })
      )

    {csr, key} = DeliveryCredentialFixtures.client_request()

    {:ok, admission} =
      ProviderDeliveryCredentials.issue(
        scope,
        mission,
        provider.provider_id,
        transport.transport_id,
        %{"reason" => "initial_enrollment", "csr_pem" => csr},
        issuer_reference: "test-issuer",
        secret_backend: fn %{purpose: "provider_delivery_issuer"} ->
          {:ok,
           %{
             material: %{
               certificate_pem: material.client_ca_pem,
               private_key_pem: material.client_ca_key_pem
             }
           }}
        end
      )

    [leaf] = admission.credential.generations

    %{
      org: org,
      mission: mission,
      scope: scope,
      provider: provider,
      grant: grant,
      transport: transport,
      listener: listener,
      tls_peers: tls_peers,
      client: %{
        certificate: der(admission.certificate_pem),
        key: key,
        ref: admission.credential.credential_ref,
        fingerprint: leaf.fingerprint
      }
    }
  end

  defp new_mission_scope! do
    org = Cadence.Ids.new("org")
    mission = Cadence.Ids.new("mission")
    %{organization: organization} = persist_mission_scope(org, mission)
    {org, mission, admin_scope(organization)}
  end

  defp admin_scope(organization) do
    user =
      User.new(%{
        user_id: "tls-admin",
        display_name: "TLS admin",
        email: "tls-admin@example.test"
      })

    membership =
      OrganizationMembership.new(%{
        organization_id: organization.organization_id,
        user_id: user.user_id,
        role: :organization_admin
      })

    Scope.new(%{user: user, organization: organization, organization_membership: membership})
  end

  defp enable_tls!(ctx) do
    {:ok, transport} = enable_tls(ctx)
    transport
  end

  defp enable_tls(ctx, target_port \\ nil) do
    inventory =
      update_in(ctx.provider.inventory_sync_document, ["delivery_profiles", "items"], fn [
                                                                                           delivery
                                                                                         ] ->
        tls =
          delivery
          |> Map.put("version", 8)
          |> Map.put("delivery_auth", "mtls")
          |> put_in(["diagnostics", "frame_bytes"], 10)
          |> put_in(["diagnostics", "port"], target_port || delivery["diagnostics"]["port"])
          |> Map.put("egress", %{
            "source_addresses" => ctx.tls_peers,
            "delivery_credential_ref" => ctx.client.ref
          })

        [delivery, tls]
      end)

    {:ok, provider} =
      MissionProviders.update_operational_state(ctx.provider, %{
        inventory_sync_document: inventory,
        capabilities_document: %{"delivery" => %{"delivery_auth" => "mtls"}}
      })

    Transports.version_transport(ctx.org, ctx.mission, ctx.transport.transport_id, %{
      origin: :provider_managed,
      mission_provider_id: provider.provider_id,
      configuration: %{"listener" => ctx.listener},
      delivery_profile_ref: @mtls_ref
    })
  end

  defp start_listener!(ctx, transport, scid \\ 7) do
    id = transport.materialized_provider_profile_id
    {:ok, profile} = ProfileStore.fetch_provider_profile(ctx.org, ctx.mission, id)

    contact_id = Cadence.Ids.new("contact")

    base = [
      organization_id: ctx.org,
      mission_id: ctx.mission,
      realized_contact_id: contact_id,
      path_id: "tls-downlink",
      provider_binding_id: id
    ]

    journal = start_supervised!({Journal, base}, id: {:ingress_journal, contact_id})

    executor =
      start_supervised!(
        {ProviderIngressExecutor, [persistence_projector_name: :unused] ++ base},
        id: {:provider_ingress_executor, contact_id}
      )

    adapter =
      start_supervised!(
        {TCPSocket,
         [
           configuration: profile.configuration,
           provider_binding_metadata: profile.metadata,
           source_endpoint_spacecraft_scid: scid,
           direction: :downlink,
           ingress_journal_name: journal,
           ingress_executor_name: executor
         ] ++ base},
        id: {:tcp_socket_provider, contact_id}
      )

    {:ok, snapshot} = TCPSocket.snapshot(adapter)
    {adapter, journal, snapshot.port}
  end

  defp direct_transport(mission, port) do
    Transport.new(%{
      mission_id: mission,
      display_name: "Direct downlink",
      configuration: %{
        "mode" => "listen",
        "direction_capability" => "inbound",
        "host" => "127.0.0.1",
        "port" => port,
        "expected_peer_addresses" => ["127.0.0.1/32"]
      }
    })
  end

  defp connect(port, material, client \\ nil) do
    opts = [:binary, active: false, verify: :verify_peer, cacerts: [der(material.server_ca_pem)]]
    opts = if client, do: opts ++ [cert: client.certificate, key: client.key], else: opts
    :ssl.connect({127, 0, 0, 1}, port, opts, 2_000)
  end

  defp der(pem) do
    [{:Certificate, certificate, :not_encrypted}] = :public_key.pem_decode(pem)
    certificate
  end

  defp assert_rejected({:error, _reason}), do: :ok

  defp assert_rejected({:ok, peer}) do
    assert {:error, _reason} = :ssl.recv(peer, 0, 2_000)
  end

  defp received?(adapter) do
    {:ok, snapshot} = TCPSocket.snapshot(adapter)
    snapshot.downlink_bytes_received > 0
  end

  defp reason(adapter) do
    case TCPSocket.refusals(adapter) do
      {:ok, %{refusals: %{last: %{reason: reason}}}} -> reason
      _status -> nil
    end
  end

  defp eventually(fun, attempts \\ 50)
  defp eventually(fun, 0), do: fun.()

  defp eventually(fun, attempts) do
    if fun.() do
      true
    else
      Process.sleep(20)
      eventually(fun, attempts - 1)
    end
  end
end
