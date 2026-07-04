defmodule Mix.Tasks.Cadence.Dashboards.ManagedQuestdbProvision do
  @moduledoc """
  Plans or applies a Cadence-managed QuestDB dashboard data-source provision.

  ## Usage

      mix cadence.dashboards.managed_questdb_provision --plan --organization-id ORG --mission-id MISSION --data-source-id SOURCE
      mix cadence.dashboards.managed_questdb_provision --apply --organization-id ORG --mission-id MISSION --data-source-id SOURCE

  ## Options

    * `--plan` - print the redacted provisioning plan without applying migrations or writing records
    * `--apply` - apply QuestDB migrations and persist the managed data-source record
    * `--organization-id` - required organization id
    * `--mission-id` - required for `mission_isolated`
    * `--data-source-id` - required dashboard data-source id
    * `--isolation-level` - `mission_isolated` or `org_isolated`, defaults to `mission_isolated`
    * `--endpoint-ref` - non-secret endpoint reference persisted in source metadata
    * `--topology-ref` - non-secret topology reference persisted in source metadata
    * `--http-endpoint` - QuestDB HTTP endpoint for migration execution
    * `--migrations-path` - override the SQL migrations directory
    * `--host` - retained for future PGWire support
    * `--port` - retained for future PGWire support
    * `--database` - database name, defaults to QuestDB migrator config
    * `--username` - username for migration config
    * `--password` - password for migration config; never printed
    * `--actor-id` - actor recorded on apply lifecycle event
    * `--help`, `-h` - show this help
  """

  use Mix.Task

  alias Cadence.Dashboards.ManagedQuestDBProvisioning

  @shortdoc "Plan or apply managed QuestDB dashboard source provisioning"

  @impl true
  def run(args) do
    {opts, remaining, invalid} =
      OptionParser.parse(
        args,
        strict: [
          plan: :boolean,
          apply: :boolean,
          organization_id: :string,
          mission_id: :string,
          data_source_id: :string,
          isolation_level: :string,
          endpoint_ref: :string,
          topology_ref: :string,
          http_endpoint: :string,
          migrations_path: :string,
          host: :string,
          port: :integer,
          database: :string,
          username: :string,
          password: :string,
          actor_id: :string,
          help: :boolean
        ],
        aliases: [h: :help]
      )

    maybe_handle_help_or_invalid_opts(opts, remaining, invalid)
    validate_mode!(opts)

    if opts[:plan] do
      plan!(opts)
    else
      apply!(opts)
    end
  end

  defp maybe_handle_help_or_invalid_opts(opts, remaining, invalid) do
    if opts[:help] || invalid != [] || remaining != [] do
      Mix.shell().info(@moduledoc)
      maybe_raise_invalid_opts(invalid)
      maybe_raise_remaining_args(remaining)
      System.halt(0)
    end
  end

  defp maybe_raise_invalid_opts([]), do: :ok
  defp maybe_raise_invalid_opts(invalid), do: Mix.raise("Invalid options: #{inspect(invalid)}")

  defp maybe_raise_remaining_args([]), do: :ok

  defp maybe_raise_remaining_args(remaining),
    do: Mix.raise("Unexpected arguments: #{inspect(remaining)}")

  defp validate_mode!(opts) do
    case {Keyword.get(opts, :plan, false), Keyword.get(opts, :apply, false)} do
      {true, false} -> :ok
      {false, true} -> :ok
      {false, false} -> Mix.raise("Specify exactly one mode: --plan or --apply")
      {true, true} -> Mix.raise("Specify exactly one mode: --plan or --apply")
    end
  end

  defp plan!(opts) do
    case planner().(provision_attrs(opts), provision_opts(opts)) do
      {:ok, plan} ->
        print_plan(plan)

      {:error, reason} ->
        Mix.raise("Managed QuestDB provisioning plan failed: #{inspect(reason)}")
    end
  end

  defp apply!(opts) do
    case provisioner().(provision_attrs(opts), provision_opts(opts)) do
      {:ok, result} ->
        print_result(result)

      {:error, reason} ->
        Mix.raise("Managed QuestDB provisioning failed: #{inspect(reason)}")
    end
  end

  defp print_plan(plan) do
    Mix.shell().info("""
    Managed QuestDB provisioning plan.
    data_source_id: #{plan.data_source.data_source_id}
    organization_id: #{plan.data_source.organization_id}
    mission_id: #{printable(plan.data_source.mission_id)}
    isolation_level: #{plan.data_source.isolation_level}
    physical_boundary: #{plan.isolation_profile.physical_boundary}
    endpoint_ref: #{printable(Map.get(plan.data_source.metadata, :endpoint_ref))}
    topology_ref: #{printable(Map.get(plan.data_source.metadata, :topology_ref))}
    storage: #{Map.get(plan.data_source.metadata, :storage)}
    http_endpoint: #{printable(Keyword.get(plan.connection_config, :http_endpoint))}
    secret_material?: #{Keyword.get(plan.connection_config, :secret_material?, false)}
    """)
  end

  defp print_result(result) do
    Mix.shell().info("""
    Managed QuestDB provisioning applied.
    data_source_id: #{result.data_source.data_source_id}
    organization_id: #{result.data_source.organization_id}
    mission_id: #{printable(result.data_source.mission_id)}
    isolation_level: #{result.data_source.isolation_level}
    physical_boundary: #{result.isolation_profile.physical_boundary}
    endpoint_ref: #{printable(Map.get(result.data_source.metadata, "endpoint_ref"))}
    topology_ref: #{printable(Map.get(result.data_source.metadata, "topology_ref"))}
    applied_migration_count: #{length(result.applied_migrations)}
    applied_migrations: #{migration_versions(result.applied_migrations)}
    """)
  end

  defp provision_attrs(opts) do
    [
      organization_id: opts[:organization_id],
      mission_id: opts[:mission_id],
      data_source_id: opts[:data_source_id],
      isolation_level: opts[:isolation_level],
      endpoint_ref: opts[:endpoint_ref],
      topology_ref: opts[:topology_ref],
      http_endpoint: opts[:http_endpoint],
      migrations_path: opts[:migrations_path],
      host: opts[:host],
      port: opts[:port],
      database: opts[:database],
      username: opts[:username],
      password: opts[:password],
      actor_id: opts[:actor_id]
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp provision_opts(opts) do
    [
      actor_id: opts[:actor_id]
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp planner do
    configured = Application.get_env(:cadence, :dashboard_managed_questdb_provisioning, [])
    Keyword.get(configured, :planner, &ManagedQuestDBProvisioning.plan/2)
  end

  defp provisioner do
    configured = Application.get_env(:cadence, :dashboard_managed_questdb_provisioning, [])
    Keyword.get(configured, :provisioner, &ManagedQuestDBProvisioning.provision/2)
  end

  defp migration_versions([]), do: "none"

  defp migration_versions(migrations) do
    Enum.map_join(migrations, ",", & &1.version)
  end

  defp printable(nil), do: "none"
  defp printable(""), do: "none"
  defp printable(value), do: value
end
