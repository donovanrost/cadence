defmodule CadenceWeb.CommsProviderLiveTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag :config

  import Phoenix.LiveViewTest

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

  alias Cadence.TestSupport.FakeProviderClient
  alias CadenceWeb.TestFixtures

  setup do
    previous_opts = Application.get_env(:cadence_web, :ground_network_provider_live_opts)

    Application.put_env(
      :cadence_web,
      :ground_network_provider_live_opts,
      client: FakeProviderClient,
      credential_resolver: &credential_resolver/1
    )

    on_exit(fn ->
      case previous_opts do
        nil -> Application.delete_env(:cadence_web, :ground_network_provider_live_opts)
        value -> Application.put_env(:cadence_web, :ground_network_provider_live_opts, value)
      end
    end)

    :ok
  end

  test "lists mission providers and exposes the mission-scoped setup path" do
    {conn, _organization, mission} = signed_in_org_and_mission()

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/providers")

    assert has_element?(view, "#comms-providers-page")
    assert has_element?(view, "#new-provider-link")
    assert has_element?(view, "#comms-providers-page", "No ground network providers")
  end

  test "creates a simulator provider using references rather than transport or secret fields" do
    {conn, organization, mission} = signed_in_org_and_mission()

    {_account, _version, grant} =
      persist_provider_account_and_grant!(organization.organization_id, mission.mission_id)

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/comms/providers/new")

    assert has_element?(view, "#mission-provider-form")
    assert has_element?(view, "#mission-provider-account-summary")
    assert has_element?(view, "select[name='provider[provider_account_grant_id]']")
    assert has_element?(view, "select[name='provider[policy_mode]']")
    refute has_element?(view, "input[name='provider[base_url]']")
    refute has_element?(view, "input[name='provider[credential_ref]']")
    refute has_element?(view, "input[name='provider[environment_ref]']")
    refute has_element?(view, "input[name='provider[tcp_mode]']")
    refute has_element?(view, "input[name='provider[port]']")
    refute has_element?(view, "input[type='password']")

    assert {:error, {:live_redirect, %{to: target}}} =
             view
             |> form("#mission-provider-form",
               provider: %{
                 display_name: "Local Ground Network",
                 provider_account_grant_id: grant.provider_account_grant_id,
                 permitted_resource_refs: "station-alpha",
                 policy_mode: "approval_required",
                 deadline_behavior: "retain_last_accepted"
               }
             )
             |> render_submit()

    [provider] =
      GroundNetworks.list_providers(organization.organization_id, mission.mission_id)

    assert provider.display_name == "Local Ground Network"
    assert provider.provider_type == :simulator
    assert provider.client_key == :simulator_http
    assert provider.provider_account_grant_id == grant.provider_account_grant_id
    assert provider.delivery_policy_document["mode"] == "approval_required"
    assert target == ~p"/missions/#{mission.mission_id}/comms/providers/#{provider.provider_id}"
  end

  test "validates and synchronizes provider profiles without materializing Cadence spacecraft" do
    {conn, organization, mission} = signed_in_org_and_mission()
    provider = persist_provider!(organization.organization_id, mission.mission_id)

    assert Cadence.list_spacecraft(organization.organization_id, mission.mission_id) == []

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/comms/providers/#{provider.provider_id}"
      )

    assert has_element?(view, "#comms-provider-show-page")
    assert has_element?(view, "#simulated-provider-badge")
    assert has_element?(view, "#provider-control-plane-health", "Not validated")
    assert has_element?(view, "#validate-provider-button")
    assert has_element?(view, "#sync-provider-button")
    assert has_element?(view, "#provider-admin-diagnostics")
    assert has_element?(view, "#provider-admin-diagnostics-json")

    view |> element("#validate-provider-button") |> render_click()
    render_async(view)

    assert has_element?(view, "#provider-control-plane-health", "Healthy")
    assert has_element?(view, "#provider-capabilities")

    view |> element("#sync-provider-button") |> render_click()
    render_async(view)

    assert has_element?(view, "#service-profile-service-realtime-ttc-downlink")
    assert has_element?(view, "#delivery-profile-delivery-cadence-primary")
    assert has_element?(view, "#provider-service-profile-count", "1")
    assert has_element?(view, "#provider-delivery-profile-count", "1")
    assert Cadence.list_spacecraft(organization.organization_id, mission.mission_id) == []
  end

  test "progressively renders delivery limits and rejects mission resource widening" do
    {conn, organization, mission} = signed_in_org_and_mission()

    {_account, _version, grant} =
      persist_provider_account_and_grant!(organization.organization_id, mission.mission_id)

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/comms/providers/new")

    assert has_element?(view, "#mission-provider-approval-policy-guidance")
    refute has_element?(view, "#mission-provider-bounded-policy-fields")

    view
    |> form("#mission-provider-form",
      provider: %{
        display_name: "Bounded Simulator",
        provider_account_grant_id: grant.provider_account_grant_id,
        policy_mode: "bounded_automatic",
        deadline_behavior: "retain_last_accepted"
      }
    )
    |> render_change()

    assert has_element?(view, "#mission-provider-bounded-policy-fields")
    assert has_element?(view, "input[name='provider[maximum_later_start_shift_seconds]']")

    view
    |> form("#mission-provider-form",
      provider: %{
        display_name: "Bounded Simulator",
        provider_account_grant_id: grant.provider_account_grant_id,
        permitted_resource_refs: "station-beta",
        policy_mode: "bounded_automatic",
        maximum_earlier_start_shift_seconds: "0",
        maximum_later_start_shift_seconds: "60",
        maximum_earlier_end_shift_seconds: "0",
        maximum_later_end_shift_seconds: "60",
        minimum_retained_duration_seconds: "300",
        approved_station_substitutions: "station-alpha",
        deadline_behavior: "retain_last_accepted"
      }
    )
    |> render_submit()

    assert GroundNetworks.list_providers(organization.organization_id, mission.mission_id) == []
  end

  test "archives a provider from its show page" do
    {conn, organization, mission} = signed_in_org_and_mission()
    provider = persist_provider!(organization.organization_id, mission.mission_id)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/comms/providers/#{provider.provider_id}"
      )

    assert {:error, {:live_redirect, %{to: target}}} =
             view |> element("#archive-provider-button") |> render_click()

    assert target == ~p"/missions/#{mission.mission_id}/comms/providers"

    assert GroundNetworks.list_providers(
             organization.organization_id,
             mission.mission_id
           ) == []
  end

  test "requires authentication for provider configuration", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(conn, ~p"/missions/some-mission/comms/providers")
  end

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()

    _membership =
      TestFixtures.grant_membership!(user, organization, role: :organization_admin)

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

  defp credential_resolver("config://simulator-test"), do: {:ok, "test-token"}
  defp credential_resolver("provider-credential-" <> _suffix), do: {:ok, "test-token"}
  defp credential_resolver(reference), do: {:error, {:credential_reference_not_found, reference}}
end
