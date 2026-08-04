defmodule Cadence.Management.DataSources.Lifecycle do
  @moduledoc false

  alias Cadence.DataSources.DataSource

  def reconcile_tsdb_backend(data_source_id, attrs, opts, {fetch_fun, persist_fun})
      when is_binary(data_source_id) and is_map(attrs) and is_list(opts) do
    occurred_at = occurred_at(attrs, opts)

    with {:ok, %DataSource{} = current} <- fetch_fun.(data_source_id),
         :ok <- validate_dedicated_byo_tsdb_backend(current) do
      lifecycle_metadata =
        tsdb_backend_lifecycle_metadata(
          current,
          attrs,
          occurred_at,
          "reconcile",
          "reconciled",
          "reconciled_at"
        )

      payload =
        opts
        |> Keyword.get(:payload, %{})
        |> Map.merge(%{
          operation: "reconcile_tsdb_backend",
          data_source_id: current.data_source_id,
          deployment_backend: Map.get(lifecycle_metadata, "backend"),
          deployment_boundary: Map.get(lifecycle_metadata, "physical_boundary"),
          lifecycle_status: Map.get(lifecycle_metadata, "status")
        })

      current
      |> put_tsdb_backend_lifecycle(lifecycle_metadata)
      |> persist_fun.(
        opts
        |> Keyword.put(:occurred_at, occurred_at)
        |> Keyword.put(:payload, payload)
      )
    end
  end

  def request_tsdb_backend_deprovisioning(
        data_source_id,
        attrs,
        opts,
        {fetch_fun, persist_fun}
      )
      when is_binary(data_source_id) and is_map(attrs) and is_list(opts) do
    occurred_at = occurred_at(attrs, opts)

    with {:ok, %DataSource{} = current} <- fetch_fun.(data_source_id),
         :ok <- validate_dedicated_byo_tsdb_backend(current) do
      lifecycle_metadata =
        tsdb_backend_lifecycle_metadata(
          current,
          attrs,
          occurred_at,
          "deprovision",
          "deprovision_requested",
          "deprovision_requested_at"
        )

      payload =
        opts
        |> Keyword.get(:payload, %{})
        |> Map.merge(%{
          operation: "request_tsdb_backend_deprovisioning",
          data_source_id: current.data_source_id,
          deployment_backend: Map.get(lifecycle_metadata, "backend"),
          deployment_boundary: Map.get(lifecycle_metadata, "physical_boundary"),
          lifecycle_status: Map.get(lifecycle_metadata, "status")
        })

      current
      |> put_tsdb_backend_lifecycle(lifecycle_metadata)
      |> then(fn %DataSource{} = source ->
        %DataSource{source | status: :disabled, disabled_at: occurred_at}
      end)
      |> persist_fun.(
        opts
        |> Keyword.put(:occurred_at, occurred_at)
        |> Keyword.put(:payload, payload)
      )
    end
  end

  def request_tsdb_backend_provisioning(data_source_id, attrs, opts, callbacks)
      when is_binary(data_source_id) and is_map(attrs) and is_list(opts) do
    {fetch_fun, persist_fun} = callbacks
    occurred_at = occurred_at(attrs, opts)

    with {:ok, %DataSource{} = current} <- fetch_fun.(data_source_id),
         :ok <- validate_dedicated_byo_tsdb_backend(current) do
      lifecycle_metadata =
        tsdb_backend_lifecycle_metadata(
          current,
          attrs,
          occurred_at,
          "provision",
          "provision_requested",
          "provision_requested_at"
        )

      payload =
        opts
        |> Keyword.get(:payload, %{})
        |> Map.merge(%{
          operation: "request_tsdb_backend_provisioning",
          data_source_id: current.data_source_id,
          deployment_backend: Map.get(lifecycle_metadata, "backend"),
          deployment_boundary: Map.get(lifecycle_metadata, "physical_boundary"),
          lifecycle_status: Map.get(lifecycle_metadata, "status")
        })

      current
      |> put_tsdb_backend_lifecycle(lifecycle_metadata)
      |> persist_fun.(
        opts
        |> Keyword.put(:occurred_at, occurred_at)
        |> Keyword.put(:payload, payload)
      )
    end
  end

  def complete_tsdb_backend_provisioning(data_source_id, attrs, opts, callbacks)
      when is_binary(data_source_id) and is_map(attrs) and is_list(opts) do
    {fetch_fun, persist_fun} = callbacks
    occurred_at = occurred_at(attrs, opts)

    with {:ok, %DataSource{} = current} <- fetch_fun.(data_source_id),
         :ok <- validate_dedicated_byo_tsdb_backend(current) do
      lifecycle_metadata =
        tsdb_backend_lifecycle_metadata(
          current,
          attrs,
          occurred_at,
          "provision",
          "provisioned",
          "provisioned_at"
        )

      payload =
        opts
        |> Keyword.get(:payload, %{})
        |> Map.merge(%{
          operation: "complete_tsdb_backend_provisioning",
          data_source_id: current.data_source_id,
          deployment_backend: Map.get(lifecycle_metadata, "backend"),
          deployment_boundary: Map.get(lifecycle_metadata, "physical_boundary"),
          lifecycle_status: Map.get(lifecycle_metadata, "status")
        })

      current
      |> put_tsdb_backend_lifecycle(lifecycle_metadata)
      |> then(fn %DataSource{} = source ->
        %DataSource{source | status: :active, disabled_at: nil}
      end)
      |> persist_fun.(
        opts
        |> Keyword.put(:occurred_at, occurred_at)
        |> Keyword.put(:payload, payload)
      )
    end
  end

  def complete_tsdb_backend_deprovisioning(data_source_id, attrs, opts, callbacks)
      when is_binary(data_source_id) and is_map(attrs) and is_list(opts) do
    {fetch_fun, persist_fun} = callbacks
    occurred_at = occurred_at(attrs, opts)

    with {:ok, %DataSource{} = current} <- fetch_fun.(data_source_id),
         :ok <- validate_dedicated_byo_tsdb_backend(current) do
      lifecycle_metadata =
        tsdb_backend_lifecycle_metadata(
          current,
          attrs,
          occurred_at,
          "deprovision",
          "deprovisioned",
          "deprovisioned_at"
        )

      payload =
        opts
        |> Keyword.get(:payload, %{})
        |> Map.merge(%{
          operation: "complete_tsdb_backend_deprovisioning",
          data_source_id: current.data_source_id,
          deployment_backend: Map.get(lifecycle_metadata, "backend"),
          deployment_boundary: Map.get(lifecycle_metadata, "physical_boundary"),
          lifecycle_status: Map.get(lifecycle_metadata, "status")
        })

      current
      |> put_tsdb_backend_lifecycle(lifecycle_metadata)
      |> then(fn %DataSource{} = source ->
        %DataSource{source | status: :disabled, disabled_at: source.disabled_at || occurred_at}
      end)
      |> persist_fun.(
        opts
        |> Keyword.put(:occurred_at, occurred_at)
        |> Keyword.put(:payload, payload)
      )
    end
  end

  defp validate_dedicated_byo_tsdb_backend(%DataSource{
         kind: :byo_tsdb,
         isolation_level: isolation_level
       })
       when isolation_level in [:org_isolated, :mission_isolated],
       do: :ok

  defp validate_dedicated_byo_tsdb_backend(%DataSource{kind: :byo_tsdb}),
    do: {:error, :dedicated_tsdb_backend_required}

  defp validate_dedicated_byo_tsdb_backend(%DataSource{}),
    do: {:error, :byo_tsdb_backend_required}

  defp tsdb_backend_lifecycle_metadata(
         %DataSource{} = source,
         attrs,
         occurred_at,
         operation,
         default_status,
         observed_at_key
       ) do
    isolation_profile = DataSource.isolation_profile(source)

    %{
      "operation" => operation,
      "status" => text(get_attr(attrs, :status, default_status)),
      observed_at_key => DateTime.to_iso8601(occurred_at),
      "backend" =>
        text(Map.get(isolation_profile, :storage) || metadata_value(source.metadata, :storage)),
      "physical_boundary" => text(Map.get(isolation_profile, :physical_boundary)),
      "endpoint_ref" => text(Map.get(isolation_profile, :endpoint_ref)),
      "topology_ref" => text(Map.get(isolation_profile, :topology_ref)),
      "job_id" => text(get_attr(attrs, :job_id)),
      "run_id" => text(get_attr(attrs, :run_id)),
      "executor_status" => text(executor_status(get_attr(attrs, :executor_result)))
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, "", "none"] end)
    |> Map.new()
  end

  defp put_tsdb_backend_lifecycle(%DataSource{} = source, lifecycle_metadata) do
    metadata =
      source.metadata
      |> normalize_metadata_map()
      |> Map.put("tsdb_backend_lifecycle", lifecycle_metadata)

    %DataSource{source | metadata: metadata}
  end

  defp metadata_value(metadata, key) when is_map(metadata) and is_atom(key) do
    Map.get(metadata, key, Map.get(metadata, Atom.to_string(key)))
  end

  defp metadata_value(_metadata, _key), do: nil

  defp normalize_metadata_map(metadata) when is_map(metadata), do: metadata
  defp normalize_metadata_map(_metadata), do: %{}

  defp executor_status(%{} = result), do: metadata_value(result, :status)
  defp executor_status(_result), do: nil

  defp occurred_at(attrs, opts) do
    attrs
    |> get_attr(:occurred_at, Keyword.get(opts, :occurred_at, DateTime.utc_now()))
    |> DateTime.truncate(:microsecond)
  end

  defp text(nil), do: "none"
  defp text(value) when is_atom(value), do: Atom.to_string(value)
  defp text(value) when is_binary(value), do: value
  defp text(value), do: to_string(value)

  defp get_attr(attrs, key, default \\ nil) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
  end
end
