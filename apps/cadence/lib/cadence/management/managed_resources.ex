defmodule Cadence.Management.ManagedResources do
  @moduledoc "Management-plane boundary for desired managed-resource lifecycle."

  alias Cadence.Management.DataSources
  alias Cadence.Management.ManagedResources.ManagedResourceRequest

  @spec request_tsdb_backend(binary(), ManagedResourceRequest.operation(), map(), keyword()) ::
          {:ok, ManagedResourceRequest.t()} | {:error, term()}
  def request_tsdb_backend(data_source_id, operation, attrs \\ %{}, opts \\ [])
      when operation in [:provision, :deprovision] and is_map(attrs) and is_list(opts) do
    result =
      case operation do
        :provision ->
          DataSources.request_tsdb_backend_provisioning(data_source_id, attrs, opts)

        :deprovision ->
          DataSources.request_tsdb_backend_deprovisioning(data_source_id, attrs, opts)
      end

    with {:ok, source} <- result do
      requested_at = requested_at(source, operation, opts)

      {:ok,
       ManagedResourceRequest.new(source, operation, requested_at, Keyword.get(opts, :run_id))}
    end
  end

  @spec reconcile_tsdb_backend(binary(), map(), keyword()) :: {:ok, struct()} | {:error, term()}
  def reconcile_tsdb_backend(data_source_id, attrs \\ %{}, opts \\ []) do
    DataSources.reconcile_tsdb_backend(data_source_id, attrs, opts)
  end

  @spec complete_tsdb_backend(binary(), ManagedResourceRequest.operation(), map(), keyword()) ::
          {:ok, struct()} | {:error, term()}
  def complete_tsdb_backend(data_source_id, operation, attrs \\ %{}, opts \\ [])
      when operation in [:provision, :deprovision] and is_map(attrs) and is_list(opts) do
    case operation do
      :provision ->
        DataSources.complete_tsdb_backend_provisioning(data_source_id, attrs, opts)

      :deprovision ->
        DataSources.complete_tsdb_backend_deprovisioning(data_source_id, attrs, opts)
    end
  end

  @spec fetch_requested_tsdb_backend(binary()) ::
          {:ok, ManagedResourceRequest.t()} | {:error, term()}
  def fetch_requested_tsdb_backend(data_source_id) do
    with {:ok, source} <- DataSources.fetch_data_source(data_source_id),
         lifecycle when is_map(lifecycle) <-
           Map.get(source.metadata, "tsdb_backend_lifecycle", %{}),
         {:ok, operation, timestamp} <- requested_operation(lifecycle),
         {:ok, requested_at, _offset} <- DateTime.from_iso8601(timestamp) do
      {:ok, ManagedResourceRequest.new(source, operation, requested_at)}
    else
      _not_requested -> {:error, :managed_resource_action_not_requested}
    end
  end

  defdelegate fetch_data_source(data_source_id), to: DataSources
  defdelegate list_data_sources(organization_id \\ nil, mission_id \\ nil), to: DataSources

  defp requested_at(source, operation, opts) do
    lifecycle = Map.get(source.metadata, "tsdb_backend_lifecycle", %{})

    timestamp =
      case operation do
        :provision -> Map.get(lifecycle, "provision_requested_at")
        :deprovision -> Map.get(lifecycle, "deprovision_requested_at")
      end

    case timestamp && DateTime.from_iso8601(timestamp) do
      {:ok, datetime, _offset} -> datetime
      _other -> Keyword.get(opts, :occurred_at, DateTime.utc_now())
    end
  end

  defp requested_operation(%{
         "operation" => "provision",
         "status" => "provision_requested",
         "provision_requested_at" => timestamp
       }),
       do: {:ok, :provision, timestamp}

  defp requested_operation(%{
         "operation" => "deprovision",
         "status" => "deprovision_requested",
         "deprovision_requested_at" => timestamp
       }),
       do: {:ok, :deprovision, timestamp}

  defp requested_operation(_lifecycle), do: {:error, :managed_resource_action_not_requested}
end
