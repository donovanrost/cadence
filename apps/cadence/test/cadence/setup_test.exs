defmodule Cadence.SetupTest do
  use Cadence.DataCase, async: false

  alias Cadence.Auth.Scope
  alias Cadence.Organizations.Organization
  alias Cadence.Setup.Workflow

  @bootstrap_admin_email "bootstrap-admin@example.com"
  @bootstrap_admin_password "bootstrap-password-123"

  setup do
    previous_bootstrap_admin = Application.get_env(:cadence, :bootstrap_admin, [])

    Application.put_env(:cadence, :bootstrap_admin,
      enabled: true,
      user_id: "user_bootstrap_admin",
      email: @bootstrap_admin_email,
      display_name: "Bootstrap Admin",
      password: @bootstrap_admin_password,
      session_ttl_seconds: 3600
    )

    assert {:ok, user} = Cadence.ensure_bootstrap_admin()

    on_exit(fn ->
      Application.put_env(:cadence, :bootstrap_admin, previous_bootstrap_admin)
    end)

    {:ok, current_scope: Scope.new(%{user: user})}
  end

  test "concurrent initial organization creation returns a predictable conflict", %{
    current_scope: current_scope
  } do
    organizations = [
      Organization.new(%{display_name: "Cadence Alpha", slug: "cadence-alpha"}),
      Organization.new(%{display_name: "Cadence Bravo", slug: "cadence-bravo"})
    ]

    start_ref = make_ref()

    tasks =
      Enum.map(organizations, fn organization ->
        Task.async(fn ->
          receive do
            ^start_ref ->
              Cadence.create_initial_setup_organization(current_scope, organization)
          end
        end)
      end)

    Enum.each(tasks, fn task -> send(task.pid, start_ref) end)

    results = Enum.map(tasks, &Task.await(&1, :infinity))

    assert Enum.count(
             results,
             &match?(
               {:ok,
                %{
                  organization: %Organization{},
                  workflow: %Workflow{current_step: :pending_durable_admin_handoff}
                }},
               &1
             )
           ) == 1

    assert Enum.count(results, &(&1 == {:error, :setup_tenant_already_created})) == 1

    assert [_persisted_organization] = Cadence.list_organizations()

    assert {:ok, %Workflow{current_step: :pending_durable_admin_handoff}} =
             Cadence.fetch_initial_setup_workflow()
  end
end
