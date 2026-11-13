defmodule CadenceWeb.OpsDataSourcesLive.WriteGuard do
  @moduledoc """
  Which data sources, bindings and deployment runs the data-sources page may change.

  Every write handler acted on the id the browser sent, with no organization or mission check:
  an organization admin could disable, provision, probe or rotate another tenant's source, or a
  platform-shared one every tenant uses (organization_id nil, e.g. managed_questdb_primary), and
  registering an existing id overwrote it. Now a write needs the record to be visible to this
  mission (`list_data_sources/2`, `list_data_bindings/2`) and owned by the caller's organization;
  a platform-shared one needs a platform admin in admin mode.
  """

  alias Cadence.Auth.Scope
  alias Cadence.DataSources.{DataBinding, DataSource}
  alias Cadence.Jobs
  alias Cadence.Management.DataSources

  @doc "The source behind `data_source_id`, if this mission's caller may change it."
  @spec source(Scope.t(), binary(), term()) ::
          {:ok, DataSource.t()} | {:error, :data_source_not_found | :platform_source}
  def source(%Scope{} = scope, mission_id, data_source_id) when is_binary(data_source_id) do
    case Enum.find(
           DataSources.list_data_sources(scope.organization_id, mission_id),
           &(&1.data_source_id == data_source_id)
         ) do
      nil -> {:error, :data_source_not_found}
      %DataSource{} = source -> with :ok <- writable(scope, source), do: {:ok, source}
    end
  end

  def source(_scope, _mission_id, _data_source_id), do: {:error, :data_source_not_found}

  @doc "A credential reference may be rotated only through the writable source it belongs to."
  @spec credential(Scope.t(), binary(), term(), term()) ::
          {:ok, DataSource.t()} | {:error, term()}
  def credential(%Scope{} = scope, mission_id, data_source_id, credentials_ref) do
    case source(scope, mission_id, data_source_id) do
      {:ok, %DataSource{credentials_ref: ^credentials_ref} = source}
      when is_binary(credentials_ref) ->
        {:ok, source}

      {:ok, %DataSource{}} ->
        {:error, :scope_mismatch}

      error ->
        error
    end
  end

  @doc "A binding may be repointed only when it's the caller's organization's own."
  @spec binding(Scope.t(), DataBinding.t()) :: :ok | {:error, :platform_source | :scope_mismatch}
  def binding(%Scope{} = scope, %DataBinding{} = binding), do: writable(scope, binding)

  @doc "A deployment run may be retried or requeued only for this mission's own source."
  @spec job(Scope.t(), binary(), term()) :: :ok | {:error, term()}
  def job(%Scope{} = scope, mission_id, job_id) when is_binary(job_id) do
    with {:ok, job} <- Jobs.fetch_job(job_id),
         true <- job.mission_id == mission_id || {:error, :job_not_found} do
      case payload_value(job.payload, :data_source_id) do
        id when is_binary(id) -> job_source(scope, mission_id, id, job.payload)
        _no_source -> :ok
      end
    end
  end

  def job(_scope, _mission_id, _job_id), do: {:error, :job_not_found}

  # A provisioning run can come before its source exists (the run creates it): then the run
  # itself must carry the caller's organization.
  defp job_source(scope, mission_id, data_source_id, payload) do
    case source(scope, mission_id, data_source_id) do
      {:ok, _source} -> :ok
      {:error, :data_source_not_found} -> uncreated_source(scope, data_source_id, payload)
      error -> error
    end
  end

  defp uncreated_source(scope, data_source_id, payload) do
    created? = match?({:ok, _}, DataSources.fetch_data_source(data_source_id))

    if not created? and payload_value(payload, :organization_id) == scope.organization_id,
      do: :ok,
      else: {:error, :data_source_not_found}
  end

  @doc "Registering never overwrites an existing source (persist_data_source/2 upserts by id)."
  @spec new_source_id(binary()) :: :ok | {:error, :data_source_exists}
  def new_source_id(data_source_id) do
    case DataSources.fetch_data_source(data_source_id) do
      {:ok, _existing} -> {:error, :data_source_exists}
      _not_found -> :ok
    end
  end

  # todo(authz): Cedar should decide who may change a data source or binding (organization
  # admins for their organization's own today; platform admins in admin mode for shared ones).
  defp writable(%Scope{organization_id: organization_id}, %{organization_id: organization_id})
       when is_binary(organization_id),
       do: :ok

  defp writable(%Scope{} = scope, %{organization_id: nil}) do
    if Scope.admin_mode?(scope), do: :ok, else: {:error, :platform_source}
  end

  defp writable(_scope, _record), do: {:error, :scope_mismatch}

  defp payload_value(payload, key) when is_map(payload),
    do: Map.get(payload, key) || Map.get(payload, Atom.to_string(key))

  defp payload_value(_payload, _key), do: nil
end
