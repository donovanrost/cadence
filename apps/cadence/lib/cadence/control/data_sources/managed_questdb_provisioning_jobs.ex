defmodule Cadence.Control.DataSources.ManagedQuestDBProvisioningJobs do
  @moduledoc """
  Durable job boundary for managed QuestDB data-source provisioning.

  The queued request is deliberately redacted. Secret material and injected
  migration functions are runtime execution concerns supplied through deployment
  config, not durable job payload.
  """

  alias Cadence.Ids
  alias Cadence.Jobs

  alias Cadence.Control.DataSources.ManagedQuestDBProvisioning

  @job_type :managed_questdb_provisioning

  @durable_attrs [
    :data_source_id,
    :organization_id,
    :mission_id,
    :isolation_level,
    :endpoint_ref,
    :topology_ref,
    :realm,
    :http_endpoint,
    :hostname,
    :host,
    :port,
    :database,
    :username,
    :migrations_path,
    :capabilities,
    :actor_id
  ]

  @redacted_attrs [:password, :exec_fun, :migrator]

  @type enqueue_result :: {:ok, Jobs.Job.t()} | {:error, term()}
  @type policy :: %{
          required(:provisioner) => (map(), keyword() -> {:ok, map()} | {:error, term()}),
          required(:execution_opts) => keyword()
        }

  @spec enqueue(map(), keyword()) :: enqueue_result()
  def enqueue(attrs, opts \\ []) when is_map(attrs) and is_list(opts) do
    with {:ok, mission_id} <- mission_id(attrs) do
      Jobs.enqueue(@job_type, mission_id, run_id(attrs, opts), payload(attrs))
    end
  end

  @doc """
  Executes with the current application configuration for public compatibility.

  The application-started durable worker uses `handler/1` with a policy captured
  at startup, so its runs do not reread global configuration.
  """
  @spec execute_enqueued_run(binary()) :: {:ok, map()} | {:error, term()}
  def execute_enqueued_run(run_id) when is_binary(run_id) do
    configured_policy =
      :cadence
      |> Application.get_env(:managed_questdb_provisioning, [])
      |> policy()

    execute_enqueued_run(run_id, configured_policy)
  end

  @spec execute_enqueued_run(binary(), policy()) :: {:ok, map()} | {:error, term()}
  def execute_enqueued_run(run_id, %{provisioner: provisioner, execution_opts: execution_opts})
      when is_binary(run_id) and is_function(provisioner, 2) and is_list(execution_opts) do
    with {:ok, job} <- Jobs.fetch_job_for_run(@job_type, run_id),
         {:ok, _plan} <- ManagedQuestDBProvisioning.plan(job.payload, execution_opts) do
      provisioner.(job.payload, execution_opts)
    end
  end

  @doc false
  @spec policy(keyword()) :: policy()
  def policy(config) when is_list(config) do
    execution_opts =
      config
      |> Keyword.get(:execution_opts, [])
      |> Keyword.merge(Keyword.take(config, [:migrator, :exec_fun, :password, :timeout]))

    %{
      provisioner: Keyword.get(config, :provisioner, &ManagedQuestDBProvisioning.provision/2),
      execution_opts: execution_opts
    }
  end

  @doc false
  @spec handler(policy()) :: (binary() -> {:ok, map()} | {:error, term()})
  def handler(%{} = policy) do
    fn run_id -> execute_enqueued_run(run_id, policy) end
  end

  @spec job_type() :: atom()
  def job_type, do: @job_type

  defp mission_id(attrs) do
    case get_attr(attrs, :mission_id) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> {:error, {:required_managed_questdb_job_field_missing, :mission_id}}
    end
  end

  defp run_id(attrs, opts) do
    Keyword.get(opts, :run_id) ||
      get_attr(attrs, :provisioning_run_id) ||
      Ids.new("managed_questdb_provisioning")
  end

  defp payload(attrs) do
    attrs
    |> Map.take(@durable_attrs ++ Enum.map(@durable_attrs, &Atom.to_string/1))
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
    |> Map.put("provisioning_kind", "managed_questdb")
    |> Map.put("redacted_fields", Enum.map(@redacted_attrs, &Atom.to_string/1))
  end

  defp get_attr(attrs, key), do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
end
