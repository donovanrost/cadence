defmodule Cadence.Secrets.EnvBackendTest do
  @moduledoc """
  What a tenant names for the env backend is scoped to its organization (api-ops' security
  sweep, api's review, 11-15): a variable it may read, and a configured material profile it may
  select. Refused names are never read, and no error carries a value.
  """
  use ExUnit.Case, async: true

  alias Cadence.Secrets.{EnvBackend, Resolver}

  @local [secret_backend: EnvBackend, allow_env_secret_backend?: true]
  @org_a "org-northlight"
  @org_b "org_b"

  @profiles %{
    "org_a_questdb" => %{
      "organization_id" => "org-northlight",
      "username_env" => "QUESTDB_A_USER",
      "password_env" => "QUESTDB_A_PASSWORD"
    },
    "platform_questdb" => %{username_env: "QUESTDB_USER", password_env: "QUESTDB_PASSWORD"}
  }

  # Fails the test if the backend reads a variable it should have refused first.
  defp env_reader(values) do
    fn name ->
      case Map.fetch(values, name) do
        {:ok, value} -> value
        :error -> flunk("read #{name}, which should have been refused before reading")
      end
    end
  end

  test "an organization's prefix is its id, upper-cased, non-alphanumerics as _" do
    assert EnvBackend.tenant_prefix(@org_a) == "CADENCE_TENANT_ORG_NORTHLIGHT_"
  end

  describe "a provider credential's variable (backend_key)" do
    test "the organization's own prefix resolves" do
      name = EnvBackend.tenant_prefix(@org_a) <> "TOKEN"
      descriptor = %{reference: "cred", backend_key: name, organization_id: @org_a}

      assert {:ok, %{material: %{value: "tenant-token"}}} =
               Resolver.resolve(
                 descriptor,
                 @local ++ [env_reader: env_reader(%{name => "tenant-token"})]
               )
    end

    test "another organization's prefix is refused without being read" do
      name = EnvBackend.tenant_prefix(@org_a) <> "TOKEN"
      descriptor = %{reference: "cred", backend_key: name, organization_id: @org_b}

      assert {:error, :env_credential_name_not_allowed} =
               Resolver.resolve(descriptor, @local ++ [env_reader: env_reader(%{})])
    end

    test "the bare tenant prefix names nobody" do
      refute EnvBackend.allowed_name?(EnvBackend.tenant_prefix(@org_a), @org_a, env_allow: [])
      refute EnvBackend.allowed_name?("CADENCE_TENANT_X", nil, env_allow: [])
    end

    for name <-
          ~w(SECRET_KEY_BASE DATABASE_URL RELEASE_COOKIE CADENCE_OPPORTUNITY_CAPABILITY_SECRET) do
      test "the platform's own #{name} is refused without being read" do
        descriptor = %{reference: "cred", backend_key: unquote(name), organization_id: @org_a}

        assert {:error, :env_credential_name_not_allowed} =
                 Resolver.resolve(descriptor, @local ++ [env_reader: env_reader(%{})])
      end
    end

    test "an operator-listed name is allowed for any organization, exactly" do
      reader = env_reader(%{"EARENDIL_DEMO_PROVIDER_TOKEN" => "demo"})

      opts =
        @local ++
          [
            env_reader: reader,
            env_allow: ["EARENDIL_DEMO_PROVIDER_TOKEN"],
            env_allow_prefixes: []
          ]

      listed = %{
        reference: "cred",
        backend_key: "EARENDIL_DEMO_PROVIDER_TOKEN",
        organization_id: @org_b
      }

      assert {:ok, _resolved} = Resolver.resolve(listed, opts)

      assert {:error, :env_credential_name_not_allowed} =
               Resolver.resolve(%{listed | backend_key: "EARENDIL_DEMO_PROVIDER_TOKEN_2"}, opts)
    end
  end

  describe "a data-source descriptor's inline *_env names" do
    test "every named variable must be the organization's, before any is read" do
      descriptor = %{
        reference: "source-cred",
        organization_id: @org_a,
        credentials_ref: "inline-profile",
        metadata: %{
          "http_endpoint_env" => EnvBackend.tenant_prefix(@org_a) <> "ENDPOINT",
          "password_env" => "DATABASE_URL"
        }
      }

      assert {:error, :env_credential_name_not_allowed} =
               Resolver.resolve(
                 descriptor,
                 @local ++ [env_reader: env_reader(%{}), env_material_profiles: %{}]
               )
    end

    test "the organization's own names resolve" do
      endpoint = EnvBackend.tenant_prefix(@org_a) <> "ENDPOINT"
      token = EnvBackend.tenant_prefix(@org_a) <> "TOKEN"

      descriptor = %{
        reference: "source-cred",
        organization_id: @org_a,
        credentials_ref: "inline-profile",
        metadata: %{"http_endpoint_env" => endpoint, "bearer_token_env" => token}
      }

      assert {:ok, %Cadence.Secrets.ResolvedSecret{}} =
               Resolver.resolve(
                 descriptor,
                 @local ++
                   [
                     env_reader:
                       env_reader(%{endpoint => "http://byo.example:9000", token => "t"}),
                     env_material_profiles: %{}
                   ]
               )
    end
  end

  describe "a configured material profile" do
    test "serves its own organization" do
      descriptor = %{reference: "s", organization_id: @org_a, credentials_ref: "org_a_questdb"}

      assert {:ok, %{material: %{password: "a-password"}}} =
               Resolver.resolve(
                 descriptor,
                 @local ++
                   [
                     env_reader:
                       env_reader(%{
                         "QUESTDB_A_USER" => "a",
                         "QUESTDB_A_PASSWORD" => "a-password"
                       }),
                     env_material_profiles: @profiles
                   ]
               )
    end

    test "can't be selected by another organization (by credentials_ref or material_env_profile)" do
      for descriptor <- [
            %{reference: "s", organization_id: @org_b, credentials_ref: "org_a_questdb"},
            %{
              reference: "s",
              organization_id: @org_b,
              credentials_ref: "b-own",
              metadata: %{"material_env_profile" => "org_a_questdb"}
            }
          ] do
        assert {:error, :env_material_profile_not_allowed} =
                 Resolver.resolve(
                   descriptor,
                   @local ++ [env_reader: env_reader(%{}), env_material_profiles: @profiles]
                 )
      end

      refute EnvBackend.profile_allowed?("org_a_questdb", @org_b,
               env_material_profiles: @profiles
             )

      assert EnvBackend.profile_allowed?("org_a_questdb", @org_a,
               env_material_profiles: @profiles
             )
    end

    test "an unowned profile serves only platform sources" do
      refute EnvBackend.profile_allowed?("platform_questdb", @org_a,
               env_material_profiles: @profiles
             )

      assert EnvBackend.profile_allowed?("platform_questdb", nil,
               env_material_profiles: @profiles
             )

      descriptor = %{reference: "s", organization_id: nil, credentials_ref: "platform_questdb"}

      assert {:ok, _resolved} =
               Resolver.resolve(
                 descriptor,
                 @local ++
                   [
                     env_reader:
                       env_reader(%{"QUESTDB_USER" => "admin", "QUESTDB_PASSWORD" => "p"}),
                     env_material_profiles: @profiles
                   ]
               )
    end
  end

  test "a missing allowed variable errors by name, never with a value" do
    name = EnvBackend.tenant_prefix(@org_a) <> "MISSING"
    descriptor = %{reference: "cred", backend_key: name, organization_id: @org_a}

    assert {:error, {:secret_reference_not_found, :env}} =
             Resolver.resolve(descriptor, @local ++ [env_reader: fn _name -> nil end])
  end

  test "the local backend stays refused unless the environment enables it" do
    assert {:error, :env_secret_backend_local_only} =
             Resolver.resolve(%{reference: "cred", backend_key: "CADENCE_TEST_X"},
               secret_backend: EnvBackend
             )
  end
end
