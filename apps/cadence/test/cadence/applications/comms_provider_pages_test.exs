defmodule Cadence.Applications.CommsProviderPagesTest do
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Applications.{ActionRequest, HostContext, SurfaceQueryRequest}
  alias Cadence.Applications.Comms.ActionProvider
  alias Cadence.Auth.Scope

  alias Cadence.GroundNetworks.{
    MissionProviderRegistration,
    ProviderAccountGrants,
    ProviderAccounts,
    ProviderCredentials
  }

  alias Cadence.Management.Providers
  alias Cadence.Reads.ApplicationSurfaces.CommsProviders
  alias Cadence.Reads.Comms.MissionProviders

  @org "org-provider-pages"
  @mission "mission-provider-pages"
  @now ~U[2026-09-07 12:00:00.000000Z]
  @feature Path.expand(
             "../../../../../frontend/modules/communications/src/features/providers",
             __DIR__
           )

  setup do
    %{organization: organization} = persist_mission_scope(@org, @mission)

    user =
      User.new(%{
        user_id: "provider-pages-admin",
        email: "provider-pages@example.test",
        display_name: "Admin"
      })

    membership =
      OrganizationMembership.new(%{
        user_id: user.user_id,
        organization_id: @org,
        role: :organization_admin
      })

    scope =
      Scope.new(%{
        user: user,
        organization_id: @org,
        organization: organization,
        organization_membership: membership
      })

    {:ok, _} =
      ProviderCredentials.create(
        @org,
        "pages-account",
        %{
          provider_credential_ref: "pages-credential",
          backend_type: :external,
          backend_key: "providers/pages/control-plane",
          registered_at: @now
        },
        manage_backend?: false,
        now: @now
      )

    {:ok, _, _} =
      ProviderAccounts.create(
        scope,
        %{
          provider_account_id: "pages-account",
          display_name: "Pages Simulator",
          provider_type: :simulator,
          base_url: "http://127.0.0.1:4101",
          region_ref: "local",
          environment_ref: "demo",
          credential_ref: "pages-credential",
          guardrails: %{}
        },
        validate_credential?: false,
        now: @now
      )

    {:ok, grant} =
      ProviderAccountGrants.grant(
        scope,
        @mission,
        "pages-account",
        %{
          provider_account_grant_id: "pages-grant",
          restrictions: %{},
          grant_reason: "Mission operations"
        },
        now: @now
      )

    %{scope: scope, grant: grant}
  end

  test "actual provider new, empty and populated directory, and detail DTOs satisfy their feature",
       %{scope: scope, grant: grant} do
    empty = load!(scope, "provider_list")
    assert_consumer(empty, "readList")
    form = load!(scope, "provider_new")
    assert_consumer(form, "readForm", "form-validation.ts")

    assert [%{"grant_id" => "pages-grant", "grant_version" => 1, "account_version" => 1}] =
             form["data"]["accounts"]["bindings"]

    assert {:ok, provider} = create(scope, params(grant))
    assert provider.provider_account_grant_version == grant.version
    assert provider.provider_account_version == grant.provider_account_version
    assert_consumer(load!(scope, "provider_list"), "readList")

    assert_consumer(
      load!(scope, "provider_show", %{"provider_id" => provider.provider_id}),
      "readDetail"
    )

    assert {:ok, archived} = Providers.archive_provider(scope, @mission, provider.provider_id)
    assert archived.lifecycle_state == :archived

    assert {:error, :unsupported_application_surface_query} =
             CommsProviders.load(
               scope,
               HostContext.mission(@mission),
               request("provider_show", %{"provider_id" => provider.provider_id})
             )

    assert_consumer(load!(scope, "provider_list"), "readList")
  end

  test "provider detail redacts nested credentials while retaining useful diagnostics", %{
    scope: scope,
    grant: grant
  } do
    assert {:ok, provider} = create(scope, params(grant))

    assert {:ok, _} =
             Providers.version_provider(@org, @mission, provider.provider_id, %{
               metadata: %{
                 "control_plane" => %{
                   "status" => "healthy",
                   "api_token" => "private-provider-token"
                 },
                 "sync" => %{"nested" => [%{"password" => "private-provider-password"}]}
               },
               capabilities_document: %{"authorization" => "private-provider-authorization"}
             })

    detail = load!(scope, "provider_show", %{"provider_id" => provider.provider_id})
    assert_consumer(detail, "readDetail")
    json = detail["data"]["diagnostics"]["json"]
    refute json =~ "private-provider-"
    assert Jason.decode!(json)["control_plane"]["status"] == "healthy"
    assert Jason.decode!(json)["control_plane"]["api_token"] == "[REDACTED]"
  end

  test "creation rejects changed or forged pins without persisting a provider", %{
    scope: scope,
    grant: grant
  } do
    for field <- ["provider_account_version", "provider_account_grant_version"] do
      assert {:error, :provider_account_grant_mismatch} =
               create(scope, Map.put(params(grant), field, "99"))
    end

    assert {:error, _} =
             create(scope, Map.put(params(grant), "provider_account_id", "another-account"))

    assert Providers.list_providers(@org, @mission) == []
  end

  test "foreign mission reads and creation are rejected and a no-grant mission stays empty", %{
    scope: scope,
    grant: grant
  } do
    other = "mission-provider-pages-other"
    persist_mission_scope(@org, other)

    request =
      request("provider_new", %{"provider_account_grant_id" => grant.provider_account_grant_id})

    assert {:error, _} = CommsProviders.load(scope, HostContext.mission(other), request)
    assert {:error, :provider_account_grant_mismatch} = create(scope, params(grant), other)

    assert {:ok, payload} =
             CommsProviders.load(scope, HostContext.mission(other), request("provider_new", %{}))

    assert payload["data"]["accounts"]["empty"]
    assert_consumer(payload, "readForm", "form-validation.ts", other)

    assert {:error, _} =
             CommsProviders.load(
               %{scope | organization_id: "foreign-org"},
               HostContext.mission(@mission),
               request("provider_list", %{})
             )

    assert Providers.list_providers(@org, @mission) == []
    assert Providers.list_providers(@org, other) == []
  end

  test "revoked grants cannot be bound after the form was read", %{scope: scope, grant: grant} do
    assert_consumer(load!(scope, "provider_new"), "readForm", "form-validation.ts")

    assert {:ok, _} =
             Cadence.Control.Providers.revoke_account_grant(
               scope,
               grant.provider_account_grant_id,
               "Access removed",
               now: DateTime.add(@now, 60, :second)
             )

    assert {:error, :provider_account_grant_revoked} = create(scope, params(grant))
    assert Providers.list_providers(@org, @mission) == []
    assert load!(scope, "provider_new")["data"]["accounts"]["empty"]
  end

  defp params(grant) do
    %{
      "display_name" => "Mission simulator",
      "provider_account_grant_id" => grant.provider_account_grant_id,
      "provider_account_grant_version" => Integer.to_string(grant.version),
      "provider_account_id" => grant.provider_account_id,
      "provider_account_version" => Integer.to_string(grant.provider_account_version),
      "policy_mode" => "approval_required",
      "deadline_behavior" => "retain_last_accepted"
    }
  end

  test "domain reads and registration independently reject missing and foreign scopes", %{
    scope: scope,
    grant: grant
  } do
    for invalid <- [
          %{scope | user: nil},
          %{scope | organization_membership: nil},
          %{scope | mission_id: "foreign"}
        ] do
      assert {:error, _} =
               MissionProviders.load(invalid, @mission, "provider_list")

      assert {:error, _} =
               MissionProviderRegistration.create(
                 invalid,
                 @mission,
                 params(grant)
               )
    end

    assert Providers.list_providers(@org, @mission) == []

    for page <- ~w(provider_list provider_new) do
      assert {:ok, model} = MissionProviders.load(scope, @mission, page)
      assert model == load!(scope, page)
    end
  end

  test "bounded timing policy is persisted exactly instead of being dropped by the adapter", %{
    scope: scope,
    grant: grant
  } do
    input =
      Map.merge(params(grant), %{
        "policy_mode" => "bounded_automatic",
        "maximum_earlier_start_shift_seconds" => "12",
        "maximum_later_start_shift_seconds" => "34",
        "maximum_earlier_end_shift_seconds" => "56",
        "maximum_later_end_shift_seconds" => "78",
        "minimum_retained_duration_seconds" => "90",
        "approved_station_substitutions" => " station-a, station-b "
      })

    assert {:ok, provider} = create(scope, input)

    for {key, value} <- input, String.ends_with?(key, "_seconds") do
      assert provider.delivery_policy_document[key] == String.to_integer(value)
    end

    assert provider.delivery_policy_document["approved_station_substitutions"] == [
             "station-a",
             "station-b"
           ]

    for invalid <- ["-1", "1.5", "x", "9007199254740992", "", %{}] do
      assert {:error, _} =
               create(scope, Map.put(input, "minimum_retained_duration_seconds", invalid))
    end

    assert {:error, _} = create(scope, Map.put(input, "deadline_behavior", "arbitrary"))
    assert length(Providers.list_providers(@org, @mission)) == 1
  end

  defp create(scope, params, mission \\ @mission) do
    ActionProvider.execute(scope, HostContext.mission(mission), %ActionRequest{
      application_key: "comms",
      application_version: 1,
      action_id: "create_provider",
      surface_id: "provider_new",
      surface_version: 1,
      params: %{"provider" => params}
    })
  end

  defp request(surface, params) do
    %SurfaceQueryRequest{
      application_key: "comms",
      application_version: 1,
      surface_id: surface,
      surface_version: 1,
      query_id: "cadence.comms." <> surface,
      query_version: 1,
      params: params
    }
  end

  defp load!(scope, surface, params \\ %{}) do
    assert {:ok, payload} =
             CommsProviders.load(scope, HostContext.mission(@mission), request(surface, params))

    payload
  end

  defp assert_consumer(payload, consumer, filename \\ "read-validation.ts", mission \\ @mission) do
    node =
      System.find_executable("node") || flunk("Node is required for the provider DTO contract")

    script = """
    import * as feature from #{Jason.encode!(Path.join(@feature, filename))};
    feature.#{consumer}(JSON.parse(process.argv[1]), {missionId: #{Jason.encode!(mission)}});
    """

    {output, status} =
      System.cmd(
        node,
        ["--no-warnings", "--input-type=module", "-e", script, Jason.encode!(payload)],
        stderr_to_stdout: true
      )

    assert status == 0, output
  end
end
