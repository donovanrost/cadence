defmodule Cadence.Accounts.EnvironmentAdminPolicyTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Accounts.EnvironmentAdminPolicy

  test "captures a complete enabled policy without consulting process-global state" do
    policy =
      EnvironmentAdminPolicy.from_config(
        enabled: true,
        email: "admin@example.test",
        display_name: "Flight Administrator",
        password: "secret-password"
      )

    assert policy.enabled?
    assert policy.email == "admin@example.test"
    assert policy.display_name == "Flight Administrator"
    assert policy.password == "secret-password"
  end

  test "normalizes incomplete enabled configuration to a disabled policy" do
    policy = EnvironmentAdminPolicy.from_config(enabled: true, email: "admin@example.test")

    refute policy.enabled?
    assert policy.email == nil
    assert policy.password == nil
  end

  test "does not expose the captured password through inspection" do
    policy =
      EnvironmentAdminPolicy.from_config(
        enabled: true,
        email: "admin@example.test",
        password: "secret-password"
      )

    refute inspect(policy) =~ "secret-password"
  end
end
