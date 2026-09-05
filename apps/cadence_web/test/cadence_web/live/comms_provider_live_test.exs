defmodule CadenceWeb.CommsProviderLiveTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag :config
  @async_timeout 1_000

  import CadenceWeb.AsyncLiveViewTestSupport, only: [render_async: 2, track_async_view: 1]
  import Phoenix.LiveViewTest, except: [render_async: 1, render_async: 2]

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.GroundNetworks

  alias Cadence.GroundNetworks.{
    MissionProvider,
    ProviderAccountGrants,
    ProviderAccounts,
    ProviderCredentials
  }

  alias CadenceWeb.TestFixtures

  test "authenticated provider list mount exposes its federated descriptor" do
    {conn, _organization, mission} = signed_in_org_and_mission()
    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/providers")

    assert has_element?(view, "#comms-provider-list-component.contents")

    assert_federated_descriptor(
      view,
      "comms-provider-list-component",
      "comms",
      "provider_list",
      "mission",
      mission.mission_id
    )
  end

  test "authenticated provider new mount carries mission query props" do
    {conn, _organization, mission} = signed_in_org_and_mission()
    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/providers/new")

    assert has_element?(view, "#comms-provider-new-component")

    assert_federated_descriptor(
      view,
      "comms-provider-new-component",
      "comms",
      "provider_new",
      "mission",
      mission.mission_id,
      class: "max-w-3xl space-y-6"
    )
  end

  test "creates a simulator provider using a mission-granted account" do
    {conn, organization, mission} = signed_in_org_and_mission()

    {account, version, grant} =
      persist_provider_account_and_grant!(organization.organization_id, mission.mission_id)

    view = provider_new_view!(conn, mission)

    assert_federated_descriptor(
      view,
      "comms-provider-new-component",
      "comms",
      "provider_new",
      "mission",
      mission.mission_id,
      class: "max-w-3xl space-y-6"
    )

    render_hook(view, "save", %{
      "provider" =>
        valid_provider_params(grant.provider_account_grant_id)
        |> Map.put("display_name", "Local Ground Network")
        |> Map.put("permitted_resource_refs", "station-alpha")
    })

    {target, _flash} = assert_redirect(view)
    [provider] = GroundNetworks.list_providers(organization.organization_id, mission.mission_id)

    assert provider.display_name == "Local Ground Network"
    assert provider.provider_type == :simulator
    assert provider.client_key == :simulator_http
    assert provider.provider_account_id == account.provider_account_id
    assert provider.provider_account_version == version.version
    assert provider.provider_account_grant_id == grant.provider_account_grant_id
    assert provider.provider_account_grant_version == grant.version
    assert provider.permitted_resource_refs == ["station-alpha"]
    assert target == ~p"/missions/#{mission.mission_id}/comms/providers/#{provider.provider_id}"
  end

  test "provider new rejects a grant outside the mission subject scope" do
    {conn, organization, mission} = signed_in_org_and_mission()

    {_account, _version, grant} =
      persist_provider_account_and_grant!(organization.organization_id, mission.mission_id)

    view = provider_new_view!(conn, mission)

    render_hook(view, "save", %{"provider" => valid_provider_params("ungranted")})

    assert has_element?(
             view,
             "#flash-error[role='alert']",
             "Select a Provider Account granted to this mission."
           )

    assert GroundNetworks.list_providers(organization.organization_id, mission.mission_id) == []
    assert grant.provider_account_grant_id != "ungranted"
  end

  test "authenticated provider show mount carries mission query props" do
    {conn, organization, mission} = signed_in_org_and_mission()
    provider = persist_provider!(organization.organization_id, mission.mission_id)

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/comms/providers/#{provider.provider_id}")

    assert has_element?(view, "#comms-provider-show-component.contents")

    assert_federated_descriptor(
      view,
      "comms-provider-show-component",
      "comms",
      "provider_show",
      "mission",
      mission.mission_id
    )
  end

  test "provider show rejects a provider outside the organization and mission scope" do
    {conn, _organization, mission} = signed_in_org_and_mission()
    other_org = TestFixtures.persist_org!()
    other_mission = TestFixtures.persist_mission!(other_org, slug: "other")
    provider = persist_provider!(other_org.organization_id, other_mission.mission_id)

    assert {:error, {:live_redirect, %{to: target}}} =
             live(
               conn,
               ~p"/missions/#{mission.mission_id}/comms/providers/#{provider.provider_id}"
             )

    assert target == ~p"/missions/#{mission.mission_id}/comms/providers"
  end

  test "validates and synchronizes provider profiles without materializing Cadence spacecraft" do
    {conn, organization, mission} = signed_in_org_and_mission()
    provider = persist_provider!(organization.organization_id, mission.mission_id)
    test_process = self()

    previous_provider_opts =
      Application.get_env(:cadence_web, :ground_network_provider_live_opts, [])

    Application.put_env(
      :cadence_web,
      :ground_network_provider_live_opts,
      previous_provider_opts
      |> Keyword.put(:validate_response, fn ->
        send(test_process, {:validate_provider_started, self()})

        receive do
          :finish_validate_provider -> {:ok, %{"state" => "running"}}
        after
          @async_timeout * 2 -> {:ok, %{"state" => "running"}}
        end
      end)
      |> Keyword.put(:spacecraft_response, fn ->
        send(test_process, {:sync_provider_started, self()})

        receive do
          :finish_sync_provider -> {:ok, []}
        after
          @async_timeout * 2 -> {:ok, []}
        end
      end)
    )

    on_exit(fn ->
      Application.put_env(
        :cadence_web,
        :ground_network_provider_live_opts,
        previous_provider_opts
      )
    end)

    assert Cadence.SpacecraftStore.list_spacecraft(
             organization.organization_id,
             mission.mission_id
           ) == []

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/comms/providers/#{provider.provider_id}")

    track_async_view(view)

    assert_federated_descriptor(
      view,
      "comms-provider-show-component",
      "comms",
      "provider_show",
      "mission",
      mission.mission_id
    )

    render_hook(view, "validate-provider", %{})
    assert_receive {:validate_provider_started, validate_provider_pid}, @async_timeout
    send(validate_provider_pid, :finish_validate_provider)
    render_async(view, @async_timeout)
    assert has_element?(view, "#flash-info", "Provider control plane validated.")

    {:ok, validated_provider} =
      GroundNetworks.fetch_provider(
        organization.organization_id,
        mission.mission_id,
        provider.provider_id
      )

    assert get_in(validated_provider.metadata, ["control_plane", "status"]) == "healthy"

    render_hook(view, "sync-provider", %{})
    assert_receive {:sync_provider_started, sync_provider_pid}, @async_timeout
    send(sync_provider_pid, :finish_sync_provider)
    render_async(view, @async_timeout)

    {:ok, synced_provider} =
      GroundNetworks.fetch_provider(
        organization.organization_id,
        mission.mission_id,
        provider.provider_id
      )

    assert get_in(synced_provider.inventory_sync_document, ["service_profiles", "total_count"]) ==
             1

    assert get_in(synced_provider.inventory_sync_document, ["delivery_profiles", "total_count"]) ==
             1

    assert Cadence.SpacecraftStore.list_spacecraft(
             organization.organization_id,
             mission.mission_id
           ) == []

    assert_federated_descriptor(
      view,
      "comms-provider-show-component",
      "comms",
      "provider_show",
      "mission",
      mission.mission_id
    )
  end

  test "archives a provider from its show page" do
    {conn, organization, mission} = signed_in_org_and_mission()
    provider = persist_provider!(organization.organization_id, mission.mission_id)

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/comms/providers/#{provider.provider_id}")

    assert_federated_descriptor(
      view,
      "comms-provider-show-component",
      "comms",
      "provider_show",
      "mission",
      mission.mission_id
    )

    assert {:error, {:live_redirect, %{to: target}}} = render_hook(view, "archive-provider", %{})
    assert target == ~p"/missions/#{mission.mission_id}/comms/providers"
    {^target, flash} = assert_redirect(view)
    assert flash["info"] == "Ground network provider archived."
    assert GroundNetworks.list_providers(organization.organization_id, mission.mission_id) == []
  end

  test "unauthenticated provider routes redirect to sign in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(conn, "/missions/mission-test/comms/providers/provider-test")
  end

  defp assert_federated_descriptor(
         view,
         id,
         application_key,
         surface_id,
         host_scope,
         mission_id,
         opts \\ []
       ) do
    vue = LiveVue.Test.get_vue(view, id: id)
    assert vue.component == "FederatedFullPageSurface"
    assert vue.ssr == false
    assert vue.handlers == %{}
    assert vue.class == Keyword.get(opts, :class, "contents")

    assert vue.props == %{
             "application_key" => application_key,
             "surface_id" => surface_id,
             "host_scope" => host_scope,
             "mission_id" => mission_id,
             "query_params" => %{"mission_id" => mission_id}
           }
  end

  defp valid_provider_params(grant_id) do
    %{
      "display_name" => "Ground Network Simulator",
      "provider_account_grant_id" => grant_id,
      "permitted_resource_refs" => "",
      "policy_mode" => "approval_required",
      "maximum_earlier_start_shift_seconds" => "0",
      "maximum_later_start_shift_seconds" => "0",
      "maximum_earlier_end_shift_seconds" => "0",
      "maximum_later_end_shift_seconds" => "0",
      "minimum_retained_duration_seconds" => "0",
      "approved_station_substitutions" => "",
      "deadline_behavior" => "retain_last_accepted"
    }
  end

  defp provider_new_view!(conn, mission) do
    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/providers/new")
    view
  end

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, organization, role: :organization_admin)

    mission =
      TestFixtures.persist_mission!(organization,
        slug: "provider-mission",
        display_name: "Provider Mission"
      )

    {TestFixtures.member_conn(user), organization, mission}
  end

  defp persist_provider!(organization_id, mission_id) do
    {account, account_version, grant} =
      persist_provider_account_and_grant!(organization_id, mission_id)

    provider =
      MissionProvider.new(%{
        mission_id: mission_id,
        display_name: "Ground Network Simulator",
        provider_account_id: account.provider_account_id,
        provider_account_version: account_version.version,
        provider_account_grant_id: grant.provider_account_grant_id,
        provider_account_grant_version: grant.version,
        provider_type: account_version.provider_type,
        client_key: account_version.client_key,
        base_url: account_version.base_url,
        credential_ref: account_version.credential_ref,
        environment_ref: account_version.environment_ref
      })

    {:ok, provider} = GroundNetworks.persist_provider(organization_id, provider)
    provider
  end

  defp persist_provider_account_and_grant!(organization_id, mission_id) do
    suffix = System.unique_integer([:positive])
    account_id = "provider-account-comms-#{suffix}"
    credential_ref = "provider-credential-comms-#{suffix}"
    now = ~U[2026-07-15 21:00:00.000000Z]

    {:ok, _credential} =
      ProviderCredentials.create(
        organization_id,
        account_id,
        %{
          provider_credential_ref: credential_ref,
          backend_type: :external,
          backend_key: "providers/comms/#{suffix}",
          registered_at: now
        },
        manage_backend?: false,
        now: now
      )

    {:ok, account, version} =
      ProviderAccounts.create_for_system(
        organization_id,
        %{
          provider_account_id: account_id,
          display_name: "Ground Network Simulator",
          provider_type: :simulator,
          base_url: "http://127.0.0.1:4101",
          region_ref: "local",
          environment_ref: "local-demo",
          credential_ref: credential_ref,
          guardrails: %{
            "allowed_services" => ["telemetry", "tracking"],
            "allowed_stations" => ["station-alpha", "station-beta"]
          }
        },
        %{"kind" => "system", "id" => "comms-provider-live-test"},
        validate_credential?: false,
        now: now
      )

    {:ok, grant} =
      ProviderAccountGrants.grant_for_system(
        organization_id,
        mission_id,
        account_id,
        %{restrictions: %{"allowed_stations" => ["station-alpha"]}},
        %{"kind" => "system", "id" => "comms-provider-live-test"},
        now: now
      )

    {account, version, grant}
  end
end
