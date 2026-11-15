defmodule Cadence.Secrets.EnvBackendTest do
  @moduledoc """
  A variable a tenant names as a credential is read only if this environment allows the name
  (api-ops' security sweep, 11-15), and its value never appears in an error.
  """
  use ExUnit.Case, async: true

  alias Cadence.Secrets.{EnvBackend, Resolver}

  @local [secret_backend: EnvBackend, allow_env_secret_backend?: true]

  # Fails the test if the backend reads a variable it should have refused by name first.
  defp env_reader(values) do
    fn name ->
      case Map.fetch(values, name) do
        {:ok, value} -> value
        :error -> flunk("read #{name}, which should have been refused before reading")
      end
    end
  end

  describe "a provider credential's variable (backend_key)" do
    test "an allowed name resolves" do
      descriptor = %{reference: "cred", backend_key: "CADENCE_TENANT_NORTHLIGHT_TOKEN"}

      assert {:ok, %{material: %{value: "tenant-token"}}} =
               Resolver.resolve(
                 descriptor,
                 @local ++
                   [
                     env_reader:
                       env_reader(%{"CADENCE_TENANT_NORTHLIGHT_TOKEN" => "tenant-token"})
                   ]
               )
    end

    for name <-
          ~w(SECRET_KEY_BASE DATABASE_URL RELEASE_COOKIE CADENCE_OPPORTUNITY_CAPABILITY_SECRET) do
      test "the platform's own #{name} is refused without being read" do
        descriptor = %{reference: "cred", backend_key: unquote(name)}

        assert {:error, :env_credential_name_not_allowed} =
                 Resolver.resolve(descriptor, @local ++ [env_reader: env_reader(%{})])
      end
    end

    test "an explicit allow list admits exactly its names" do
      descriptor = %{reference: "cred", backend_key: "EARENDIL_DEMO_PROVIDER_TOKEN"}
      reader = env_reader(%{"EARENDIL_DEMO_PROVIDER_TOKEN" => "demo"})

      assert {:ok, _resolved} =
               Resolver.resolve(
                 descriptor,
                 @local ++
                   [
                     env_reader: reader,
                     env_allow: ["EARENDIL_DEMO_PROVIDER_TOKEN"],
                     env_allow_prefixes: []
                   ]
               )

      assert {:error, :env_credential_name_not_allowed} =
               Resolver.resolve(
                 %{descriptor | backend_key: "EARENDIL_DEMO_PROVIDER_TOKEN_2"},
                 @local ++ [env_reader: reader, env_allow: ["EARENDIL_DEMO_PROVIDER_TOKEN"]]
               )
    end
  end

  describe "a data-source descriptor's inline *_env names" do
    test "every named variable must be allowed, before any is read" do
      descriptor = %{
        reference: "source-cred",
        credentials_ref: "inline-profile",
        metadata: %{
          "http_endpoint_env" => "CADENCE_TENANT_BYO_ENDPOINT",
          "password_env" => "DATABASE_URL"
        }
      }

      assert {:error, :env_credential_name_not_allowed} =
               Resolver.resolve(
                 descriptor,
                 @local ++ [env_reader: env_reader(%{}), env_material_profiles: %{}]
               )
    end

    test "allowed names resolve" do
      descriptor = %{
        reference: "source-cred",
        credentials_ref: "inline-profile",
        metadata: %{
          "http_endpoint_env" => "CADENCE_TENANT_BYO_ENDPOINT",
          "bearer_token_env" => "CADENCE_TENANT_BYO_TOKEN"
        }
      }

      assert {:ok, %Cadence.Secrets.ResolvedSecret{}} =
               Resolver.resolve(
                 descriptor,
                 @local ++
                   [
                     env_reader:
                       env_reader(%{
                         "CADENCE_TENANT_BYO_ENDPOINT" => "http://byo.example:9000",
                         "CADENCE_TENANT_BYO_TOKEN" => "tenant-token"
                       }),
                     env_material_profiles: %{}
                   ]
               )
    end

    test "an operator-configured profile isn't restricted (it's the platform's own)" do
      descriptor = %{reference: "source-cred", credentials_ref: "managed"}

      assert {:ok, %{material: %{password: "managed-password"}}} =
               Resolver.resolve(
                 descriptor,
                 @local ++
                   [
                     env_reader:
                       env_reader(%{
                         "QUESTDB_USER" => "admin",
                         "QUESTDB_PASSWORD" => "managed-password"
                       }),
                     env_material_profiles: %{
                       "managed" => %{
                         username_env: "QUESTDB_USER",
                         password_env: "QUESTDB_PASSWORD"
                       }
                     }
                   ]
               )
    end
  end

  test "a missing allowed variable errors by name, never with a value" do
    descriptor = %{reference: "cred", backend_key: "CADENCE_TENANT_MISSING"}

    assert {:error, reason} =
             Resolver.resolve(descriptor, @local ++ [env_reader: fn _name -> nil end])

    assert reason == {:secret_reference_not_found, :env}
  end

  test "the local backend stays refused unless the environment enables it" do
    assert {:error, :env_secret_backend_local_only} =
             Resolver.resolve(%{reference: "cred", backend_key: "CADENCE_TENANT_X"},
               secret_backend: EnvBackend
             )
  end
end
