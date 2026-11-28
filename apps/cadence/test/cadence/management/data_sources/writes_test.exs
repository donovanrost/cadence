defmodule Cadence.Management.DataSources.WritesTest do
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Auth.Scope
  alias Cadence.DataSources.{DataBinding, DataSource}
  alias Cadence.Management.DataSources
  alias Cadence.Management.DataSources.Writes

  @organization_id "org-ops-data-sources-actions"
  @mission_id "mission-ops-data-sources-actions"

  setup do
    persist_mission_scope(@organization_id, @mission_id)
    :ok
  end

  test "register-source persists the source in the caller's organization and mission" do
    request =
      request("register-source", %{
        "source" => %{
          "data_source_id" => "action-managed-source",
          "logical_source" => "telemetry",
          "kind" => "managed_tsdb",
          "isolation_level" => "mission_isolated",
          "credentials_ref" => "",
          "credential_provider" => "questdb",
          "endpoint_ref" => "",
          "material_env_profile" => "",
          "http_endpoint_env" => "",
          "storage" => "questdb"
        }
      })

    assert {:ok, %DataSource{} = source} =
             write(scope(), request)

    assert source.data_source_id == "action-managed-source"
    assert source.organization_id == @organization_id
    assert source.mission_id == @mission_id
    assert source.status == :active
    assert source.kind == :managed_tsdb
    assert source.isolation_level == :mission_isolated
  end

  test "register-source refuses an endpoint variable this environment doesn't allow" do
    request =
      request("register-source", %{
        "source" => %{
          "data_source_id" => "action-env-source",
          "logical_source" => "telemetry",
          "kind" => "byo_tsdb",
          "isolation_level" => "mission_isolated",
          "credentials_ref" => "inline-byo",
          "credential_provider" => "questdb",
          "endpoint_ref" => "",
          "material_env_profile" => "",
          "http_endpoint_env" => "DATABASE_URL",
          "storage" => "questdb"
        }
      })

    assert {:error, :env_credential_name_not_allowed} =
             write(scope(), request)

    assert {:error, _not_found} = DataSources.fetch_data_source("action-env-source")
  end

  test "register-source can't select another organization's credential profile" do
    previous = Application.get_env(:cadence, :data_source_credentials)

    Application.put_env(:cadence, :data_source_credentials,
      env_material_profiles: %{
        "other_org_questdb" => %{"organization_id" => "org-someone-else", "password_env" => "X"}
      }
    )

    on_exit(fn ->
      if previous,
        do: Application.put_env(:cadence, :data_source_credentials, previous),
        else: Application.delete_env(:cadence, :data_source_credentials)
    end)

    request =
      request("register-source", %{
        "source" => %{
          "data_source_id" => "action-profile-source",
          "logical_source" => "telemetry",
          "kind" => "byo_tsdb",
          "isolation_level" => "mission_isolated",
          "credentials_ref" => "own-ref",
          "credential_provider" => "questdb",
          "endpoint_ref" => "",
          "material_env_profile" => "other_org_questdb",
          "http_endpoint_env" => "",
          "storage" => "questdb"
        }
      })

    assert {:error, :env_material_profile_not_allowed} =
             write(scope(), request)
  end

  test "rejects a resource from another mission before domain mutation" do
    persist_mission_scope(@organization_id, "mission-other")

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: "other-mission-source",
               owner: :cadence,
               kind: :managed_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: @organization_id,
               mission_id: "mission-other",
               isolation_level: :mission_isolated,
               capabilities: %{latest?: true},
               metadata: %{storage: :questdb}
             })

    request = request("disable-source", %{"data-source-id" => "other-mission-source"})

    assert {:error, :scope_mismatch} =
             write(scope(), request)
  end

  test "rejects a cross-mission parameter" do
    request =
      request("disable-source", %{
        "data-source-id" => "source-1",
        "mission_id" => "mission-other"
      })

    assert {:error, :scope_mismatch} =
             write(scope(), request)
  end

  test "params are exact before policy or domain calls" do
    assert {:error, :malformed_action_input} =
             execute(
               request("retry-deployment-run", %{"job-id" => "job-1", "unexpected" => "rejected"})
             )
  end

  test "rejects unknown and malformed actions fail-closed" do
    assert {:error, :unsupported_action} =
             write(scope(), request("unknown-source-action", %{}))

    assert {:error, :malformed_action_input} =
             write(scope(), request("disable-source", %{"data-source-id" => self()}))
  end

  describe "writes only on the caller's own sources (shared and other-org sources are refused)" do
    setup do
      shared = persist_source!("platform-shared-source", nil, nil, :shared)
      %{shared: shared}
    end

    test "a mission operator can't disable, enable or probe a platform-shared source", c do
      for action <- ["disable-source", "probe-source", "provision-tsdb-backend"] do
        assert {:error, :platform_source} =
                 execute(request(action, %{"data-source-id" => c.shared.data_source_id}))
      end

      assert {:ok, source} = DataSources.fetch_data_source(c.shared.data_source_id)
      assert source.status == :active
    end

    test "another organization's source isn't reachable at all" do
      persist_mission_scope("org-other-tenant", "mission-other-tenant")

      persist_source!(
        "other-tenant-source",
        "org-other-tenant",
        "mission-other-tenant",
        :mission_isolated
      )

      assert {:error, :scope_mismatch} =
               execute(request("disable-source", %{"data-source-id" => "other-tenant-source"}))
    end

    test "registering an existing id never overwrites it", c do
      request =
        request("register-source", %{
          "source" => %{
            "data_source_id" => c.shared.data_source_id,
            "logical_source" => "telemetry",
            "kind" => "managed_tsdb",
            "isolation_level" => "mission_isolated",
            "credentials_ref" => "",
            "credential_provider" => "questdb",
            "endpoint_ref" => "",
            "material_env_profile" => "",
            "http_endpoint_env" => "",
            "storage" => "questdb"
          }
        })

      assert {:error, :data_source_exists} = execute(request)
      assert {:ok, source} = DataSources.fetch_data_source(c.shared.data_source_id)
      assert source.organization_id == nil
    end

    test "a platform-shared binding can't be repointed by a mission operator", c do
      {:ok, _binding} =
        DataSources.persist_data_binding(%DataBinding{
          binding_id: "platform-shared-binding",
          organization_id: nil,
          mission_id: nil,
          realm: "flight",
          logical_source: :telemetry,
          data_source_id: c.shared.data_source_id
        })

      own = persist_source!("own-source", @organization_id, @mission_id, :mission_isolated)

      assert {:error, :platform_source} =
               execute(
                 request("change-binding", %{
                   "binding" => %{
                     "binding_id" => "platform-shared-binding",
                     "data_source_id" => own.data_source_id,
                     "expected_data_source_id" => c.shared.data_source_id
                   }
                 })
               )
    end

    test "a platform-wide binding never points at an organization's own source, even for an admin",
         c do
      {:ok, _binding} =
        DataSources.persist_data_binding(%DataBinding{
          binding_id: "platform-shared-binding-target",
          organization_id: nil,
          mission_id: nil,
          realm: "flight",
          logical_source: :telemetry,
          data_source_id: c.shared.data_source_id
        })

      own = persist_source!("own-target-source", @organization_id, @mission_id, :mission_isolated)

      assert {:error, :platform_target_required} =
               write(
                 platform_admin(),
                 request("change-binding", %{
                   "binding" => %{
                     "binding_id" => "platform-shared-binding-target",
                     "data_source_id" => own.data_source_id,
                     "expected_data_source_id" => c.shared.data_source_id,
                     "reason" => "Use ours.",
                     "expected_affected_missions" => 1,
                     "expected_live_passes_total" => 0
                   }
                 })
               )

      assert {:ok, %DataBinding{data_source_id: unchanged}} =
               DataSources.fetch_data_binding("platform-shared-binding-target")

      assert unchanged == c.shared.data_source_id

      # A :shared source that still belongs to one organization isn't platform-shared either.
      org_shared = persist_source!("org-shared-target-source", @organization_id, nil, :shared)

      assert {:error, :platform_target_required} =
               write(
                 platform_admin(),
                 request("change-binding", %{
                   "binding" => %{
                     "binding_id" => "platform-shared-binding-target",
                     "data_source_id" => org_shared.data_source_id,
                     "expected_data_source_id" => c.shared.data_source_id,
                     "reason" => "Use the org's shared one.",
                     "expected_affected_missions" => 1,
                     "expected_live_passes_total" => 0
                   }
                 })
               )
    end

    test "a platform admin in admin mode may change a shared source", c do
      admin =
        Scope.new(%{
          user:
            User.new(%{
              user_id: "user-platform-admin-ds",
              email: "pa-ds@example.test",
              display_name: "PA",
              capabilities: [:platform_admin]
            }),
          organization_id: @organization_id,
          admin_mode?: true
        })

      assert {:ok, %DataSource{status: :disabled}} =
               write(
                 admin,
                 request("disable-source", %{"data-source-id" => c.shared.data_source_id})
               )
    end
  end

  describe "change-binding is confirmed against the source the operator saw" do
    setup do
      first =
        persist_source!("binding-first-source", @organization_id, @mission_id, :mission_isolated)

      second =
        persist_source!("binding-second-source", @organization_id, @mission_id, :mission_isolated)

      third =
        persist_source!("binding-third-source", @organization_id, @mission_id, :mission_isolated)

      {:ok, binding} =
        DataSources.persist_data_binding(%DataBinding{
          binding_id: "mission-expected-binding",
          organization_id: @organization_id,
          mission_id: @mission_id,
          realm: "flight",
          logical_source: :telemetry,
          data_source_id: first.data_source_id
        })

      %{binding: binding, first: first, second: second, third: third}
    end

    test "the host action refuses a switch without the expected source, or with a stale one", c do
      switch = fn binding_params ->
        execute(
          request("change-binding", %{
            "binding" =>
              Map.merge(
                %{
                  "binding_id" => c.binding.binding_id,
                  "data_source_id" => c.second.data_source_id
                },
                binding_params
              )
          })
        )
      end

      assert {:error, :malformed_action_input} = switch.(%{})

      assert {:error, {:binding_changed, current}} =
               switch.(%{"expected_data_source_id" => c.third.data_source_id})

      assert current == c.first.data_source_id
      assert {:ok, unchanged} = DataSources.fetch_data_binding(c.binding.binding_id)
      assert unchanged.data_source_id == c.first.data_source_id

      assert {:ok, %DataBinding{data_source_id: switched}} =
               switch.(%{"expected_data_source_id" => c.first.data_source_id})

      assert switched == c.second.data_source_id
    end

    test "the write re-checks the expected source, so a switch made in between isn't overwritten",
         %{binding: %DataBinding{} = binding} = c do
      # Someone else moved the binding after this switch read it.
      {:ok, _moved} =
        DataSources.persist_data_binding(%DataBinding{
          binding
          | data_source_id: c.third.data_source_id
        })

      assert {:error, {:binding_changed, current}} =
               DataSources.persist_data_binding(
                 %DataBinding{binding | data_source_id: c.second.data_source_id},
                 expected_data_source_id: c.first.data_source_id
               )

      assert current == c.third.data_source_id
      assert {:ok, kept} = DataSources.fetch_data_binding(binding.binding_id)
      assert kept.data_source_id == c.third.data_source_id
    end
  end

  defp platform_admin do
    Scope.new(%{
      user:
        User.new(%{
          user_id: "user-platform-admin-target",
          email: "pa-target@example.test",
          display_name: "PA",
          capabilities: [:platform_admin]
        }),
      organization_id: @organization_id,
      admin_mode?: true
    })
  end

  defp execute(request), do: write(scope(), request)

  defp write(scope, {action_id, params}),
    do: Writes.execute(scope, @mission_id, action_id, params)

  defp persist_source!(id, organization_id, mission_id, isolation) do
    {:ok, source} =
      DataSources.persist_data_source(%DataSource{
        data_source_id: id,
        owner: :cadence,
        kind: :managed_tsdb,
        adapter: Cadence.Dashboards.Sources.Telemetry,
        organization_id: organization_id,
        mission_id: mission_id,
        isolation_level: isolation,
        capabilities: %{latest?: true},
        metadata: %{storage: :questdb}
      })

    source
  end

  defp request(action_id, params), do: {action_id, params}

  # A person: the console's writes come from a browser session, never from a
  # service. Since #384 an organization-level action refuses a service (#282).
  defp scope do
    %Scope{
      actor_kind: :user,
      organization_id: @organization_id,
      mission_id: @mission_id,
      organization_membership: %OrganizationMembership{
        organization_id: @organization_id,
        user_id: "user-ops-data-sources",
        role: :organization_admin,
        lifecycle_state: :active
      },
      user: %User{user_id: "user-ops-data-sources", display_name: "Ops data sources tester"},
      capabilities: MapSet.new([:organization_admin])
    }
  end
end
