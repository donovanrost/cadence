defmodule Mix.Tasks.Cadence.Dashboards.ManagedQuestdbProvisionTest do
  use Cadence.ConfigCase, async: false

  alias Cadence.Dashboards.DataSource
  alias Mix.Tasks.Cadence.Dashboards.ManagedQuestdbProvision

  setup do
    previous_shell = Mix.shell()
    previous_config = Application.get_env(:cadence, :dashboard_managed_questdb_provisioning)

    Mix.shell(Mix.Shell.Process)

    on_exit(fn ->
      Mix.shell(previous_shell)

      if is_nil(previous_config) do
        Application.delete_env(:cadence, :dashboard_managed_questdb_provisioning)
      else
        Application.put_env(:cadence, :dashboard_managed_questdb_provisioning, previous_config)
      end
    end)

    :ok
  end

  test "plan mode prints redacted managed QuestDB provisioning evidence" do
    ManagedQuestdbProvision.run([
      "--plan",
      "--organization-id",
      "org-task",
      "--mission-id",
      "mission-task",
      "--data-source-id",
      "mission-task-questdb",
      "--endpoint-ref",
      "endpoint://cadence/task",
      "--topology-ref",
      "topology://cadence/task",
      "--http-endpoint",
      "http://task-questdb:9000",
      "--password",
      "task-secret"
    ])

    assert_received {:mix_shell, :info, [output]}
    assert output =~ "Managed QuestDB provisioning plan."
    assert output =~ "data_source_id: mission-task-questdb"
    assert output =~ "organization_id: org-task"
    assert output =~ "mission_id: mission-task"
    assert output =~ "isolation_level: mission_isolated"
    assert output =~ "physical_boundary: mission"
    assert output =~ "endpoint_ref: endpoint://cadence/task"
    assert output =~ "topology_ref: topology://cadence/task"
    assert output =~ "http_endpoint: http://task-questdb:9000"
    assert output =~ "secret_material?: true"
    refute output =~ "task-secret"
  end

  test "apply mode delegates to configured provisioner and prints migration summary" do
    test_pid = self()

    Application.put_env(:cadence, :dashboard_managed_questdb_provisioning,
      provisioner: fn attrs, opts ->
        send(test_pid, {:provision_args, attrs, opts})

        {:ok,
         %{
           data_source: %DataSource{
             data_source_id: attrs.data_source_id,
             organization_id: attrs.organization_id,
             mission_id: attrs.mission_id,
             isolation_level: :mission_isolated,
             metadata: %{
               "endpoint_ref" => attrs.endpoint_ref,
               "topology_ref" => attrs.topology_ref
             }
           },
           applied_migrations: [
             %{version: "20260630010101", name: "create_observations"}
           ],
           isolation_profile: %{physical_boundary: :mission},
           provisioning: %{applied_migration_count: 1}
         }}
      end
    )

    ManagedQuestdbProvision.run([
      "--apply",
      "--organization-id",
      "org-task",
      "--mission-id",
      "mission-task",
      "--data-source-id",
      "mission-task-questdb",
      "--endpoint-ref",
      "endpoint://cadence/task",
      "--topology-ref",
      "topology://cadence/task",
      "--http-endpoint",
      "http://task-questdb:9000",
      "--actor-id",
      "operator-task",
      "--password",
      "task-secret"
    ])

    assert_received {:provision_args, attrs, opts}
    assert attrs.organization_id == "org-task"
    assert attrs.mission_id == "mission-task"
    assert attrs.data_source_id == "mission-task-questdb"
    assert attrs.http_endpoint == "http://task-questdb:9000"
    assert attrs.password == "task-secret"
    assert opts[:actor_id] == "operator-task"

    assert_received {:mix_shell, :info, [output]}
    assert output =~ "Managed QuestDB provisioning applied."
    assert output =~ "data_source_id: mission-task-questdb"
    assert output =~ "applied_migration_count: 1"
    assert output =~ "applied_migrations: 20260630010101"
    refute output =~ "task-secret"
  end

  test "requires exactly one explicit mode" do
    assert_raise Mix.Error, "Specify exactly one mode: --plan or --apply", fn ->
      ManagedQuestdbProvision.run([
        "--organization-id",
        "org-task",
        "--mission-id",
        "mission-task",
        "--data-source-id",
        "mission-task-questdb"
      ])
    end

    assert_raise Mix.Error, "Specify exactly one mode: --plan or --apply", fn ->
      ManagedQuestdbProvision.run([
        "--plan",
        "--apply",
        "--organization-id",
        "org-task",
        "--mission-id",
        "mission-task",
        "--data-source-id",
        "mission-task-questdb"
      ])
    end
  end
end
