defmodule CadenceSimulator.Provider.ConfigurationTest do
  use ExUnit.Case, async: true

  alias CadenceSimulator.Provider.{Configuration, Orchestrator, Router}

  test "captures router authentication and orchestrator defaults in startup children" do
    configuration =
      Configuration.new(
        provider_http: [enabled: true, ip: {127, 0, 0, 1}, port: 41_099],
        provider_auth_required: true,
        provider_admin_api_token: "admin-token",
        provider_api_token: "provider-token",
        provider_store: [path: "/tmp/provider-configuration-test.dets"],
        provider_defaults: [definitions_path: "/tmp/provider-definitions.yaml"]
      )

    assert Configuration.router_options(configuration) ==
             [
               provider_auth: [
                 required?: true,
                 provider_admin_api_token: "admin-token",
                 provider_api_token: "provider-token"
               ]
             ]

    children = CadenceSimulator.Application.children(configuration)

    assert {Orchestrator,
            [provider_defaults: [definitions_path: "/tmp/provider-definitions.yaml"]]} in children

    assert Enum.any?(children, fn
             {Bandit, opts} ->
               Keyword.get(opts, :plug) == {Router, Configuration.router_options(configuration)}

             _other ->
               false
           end)
  end

  test "rejects an authenticated HTTP startup snapshot with a missing token" do
    assert_raise ArgumentError, fn ->
      Configuration.new(
        provider_http: [enabled: true],
        provider_auth_required: true,
        provider_admin_api_token: "admin-token",
        provider_api_token: nil
      )
    end
  end
end
