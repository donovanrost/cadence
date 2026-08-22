defmodule Cadence.Secrets.ResolverTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Secrets.{EnvBackend, MaterialPolicy, Resolver}

  test "returns ephemeral material with registry and backend identity without inspect leakage" do
    descriptor = %{
      provider_credential_ref: "provider-credential-one",
      organization_id: "org-one",
      provider_account_id: "account-one",
      registry_version: 4
    }

    backend = fn ^descriptor, _opts ->
      {:ok,
       %{
         material: %{"value" => "provider-secret"},
         backend_version: "backend-version-seven",
         fingerprint: "fingerprint-seven",
         expires_at: "2026-07-16T00:00:00Z"
       }}
    end

    assert {:ok, resolved} = Resolver.resolve(descriptor, secret_backend: backend)
    assert resolved.material == %{value: "provider-secret"}
    assert resolved.reference == "provider-credential-one"
    assert resolved.registry_version == 4
    assert resolved.backend_version == "backend-version-seven"
    assert resolved.fingerprint == "fingerprint-seven"
    assert resolved.expires_at == ~U[2026-07-16 00:00:00Z]
    refute inspect(resolved) =~ "provider-secret"
  end

  test "material policy uses allow-listed keys without atomizing external input" do
    unknown_key = "attacker_key_#{System.unique_integer([:positive])}"

    assert {:ok, %{token: "secret"}} =
             MaterialPolicy.normalize_and_validate(%{
               "token" => "secret",
               unknown_key => "ignored"
             })

    assert_raise ArgumentError, fn -> String.to_existing_atom(unknown_key) end

    assert {:error, :ambiguous_auth_material} =
             MaterialPolicy.normalize_and_validate(%{
               bearer_token: "bearer",
               username: "user",
               password: "password"
             })
  end

  test "environment backend is local-only and mutation capabilities fail closed" do
    descriptor = %{reference: "provider-credential-env", backend_key: "PROVIDER_TEST_TOKEN"}
    env_reader = fn "PROVIDER_TEST_TOKEN" -> "local-secret" end

    assert {:error, :env_secret_backend_local_only} =
             Resolver.resolve(descriptor,
               secret_backend: EnvBackend,
               env_reader: env_reader
             )

    assert {:ok, resolved} =
             Resolver.resolve(descriptor,
               secret_backend: EnvBackend,
               allow_env_secret_backend?: true,
               env_reader: env_reader
             )

    assert resolved.material == %{value: "local-secret"}

    assert {:error, {:secret_backend_capability_not_supported, :rotate}} =
             Resolver.mutate(:rotate, descriptor,
               secret_backend: EnvBackend,
               allow_env_secret_backend?: true
             )
  end
end
