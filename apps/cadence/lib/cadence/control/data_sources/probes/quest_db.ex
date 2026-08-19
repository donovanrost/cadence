defmodule Cadence.Control.DataSources.Probes.QuestDB do
  @moduledoc false

  alias Cadence.DataSources.SourceProbe

  alias Cadence.DataSources.DataSource
  alias Cadence.Telemetry.Storage.QuestDB.{ObservationReader, ObservationRow, RestClient}

  @type policy :: %{
          required(:enabled?) => boolean(),
          required(:exec_fun) => (binary(), keyword() -> {:ok, term()} | {:error, term()}),
          required(:timeout) => timeout(),
          optional(:http_endpoint) => binary() | nil
        }

  @doc """
  Probes with a policy resolved from current application configuration.

  Call `probe/3` from option-aware paths that already hold an immutable policy
  snapshot; this arity remains the compatibility boundary for legacy callers.
  """
  @spec probe(DataSource.t(), keyword()) :: SourceProbe.t()
  def probe(%DataSource{} = data_source, opts) when is_list(opts) do
    configured_policy =
      :cadence
      |> Application.get_env(:data_source_probe, [])
      |> policy()

    probe(data_source, opts, configured_policy)
  end

  @spec probe(DataSource.t(), keyword(), policy()) :: SourceProbe.t()
  def probe(%DataSource{} = data_source, opts, %{} = policy) when is_list(opts) do
    if probe_enabled?(opts, policy) do
      with {:ok, _body} <- probe_exec("SELECT 1", opts, policy),
           {:ok, schema_metadata} <- schema_probe_metadata(opts, policy) do
        SourceProbe.healthy(
          :source_probe_succeeded,
          Map.merge(probe_metadata(data_source, opts, policy), schema_metadata),
          probe_kind: :adapter
        )
      else
        {:schema_error, reason, schema_metadata} ->
          SourceProbe.degraded(
            :source_schema_probe_failed,
            probe_metadata(data_source, opts, policy)
            |> Map.merge(schema_metadata)
            |> Map.merge(schema_diagnostic_metadata(reason))
            |> Map.put(:adapter_error, safe_error(reason)),
            probe_kind: :adapter
          )

        {:error, reason} ->
          SourceProbe.unavailable(
            :source_connection_failed,
            probe_metadata(data_source, opts, policy)
            |> Map.merge(connection_diagnostic_metadata(reason))
            |> Map.put(:adapter_error, safe_error(reason)),
            probe_kind: :adapter
          )
      end
    else
      SourceProbe.unsupported(
        Map.merge(probe_metadata(data_source, opts, policy), %{
          probe_enabled?: false,
          reason: "QuestDB live probe is disabled for this environment"
        })
      )
    end
  end

  @doc false
  @spec policy(keyword()) :: policy()
  def policy(config) when is_list(config) do
    %{
      enabled?: Keyword.get(config, :questdb_enabled?, false),
      exec_fun: Keyword.get(config, :questdb_exec_fun, &RestClient.exec/2),
      http_endpoint: Keyword.get(config, :questdb_http_endpoint),
      timeout: Keyword.get(config, :questdb_timeout, 2_000)
    }
  end

  defp schema_probe_metadata(opts, policy) do
    case probe_exec(schema_probe_sql(), opts, policy) do
      {:ok, result} ->
        columns = result_columns(result)
        missing = probe_columns() -- columns

        if missing == [] do
          {:ok,
           %{
             questdb_schema_probe?: true,
             questdb_schema_table: "telemetry_observations",
             questdb_schema_columns: columns,
             adapter_reported_capabilities: %{
               latest?: true,
               range_scan?: true,
               bounded_history?: true,
               native_decimation?: true,
               watermarks?: true
             }
           }}
        else
          {:schema_error, {:missing_columns, missing},
           %{
             questdb_schema_probe?: true,
             questdb_schema_table: "telemetry_observations",
             questdb_schema_columns: columns,
             questdb_schema_missing_columns: missing,
             adapter_reported_capabilities: %{
               latest?: true,
               range_scan?: false,
               bounded_history?: false,
               native_decimation?: false,
               watermarks?: false
             }
           }}
        end

      {:error, reason} ->
        {:schema_error, reason,
         %{
           questdb_schema_probe?: false,
           questdb_schema_table: "telemetry_observations",
           adapter_reported_capabilities: %{
             latest?: false,
             range_scan?: false,
             bounded_history?: false,
             native_decimation?: false,
             watermarks?: false
           }
         }}
    end
  end

  defp schema_probe_sql do
    "SELECT #{probe_columns() |> Enum.join(", ")} FROM telemetry_observations LIMIT 0"
  end

  defp probe_columns do
    writer_columns =
      ObservationRow.columns()
      |> Enum.map(&Atom.to_string/1)

    (ObservationReader.select_columns() ++ writer_columns)
    |> Enum.uniq()
  end

  defp result_columns(%{"columns" => columns}) when is_list(columns) do
    columns
    |> Enum.map(fn
      %{"name" => name} when is_binary(name) -> name
      %{name: name} when is_binary(name) -> name
      name when is_binary(name) -> name
      _other -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp result_columns(_result), do: []

  defp safe_error({:http_error, status, _body}),
    do: "{:http_error, #{status}, :redacted_body}"

  defp safe_error(reason) when is_map(reason), do: "adapter_error"
  defp safe_error(reason), do: inspect(reason)

  defp connection_diagnostic_metadata(reason) do
    {kind, remediation} =
      case reason_category(reason) do
        :authentication_failed -> {:authentication_failed, :check_credential_material}
        :http_error -> {:http_error, :check_questdb_http_api}
        :timeout -> {:connection_timeout, :check_questdb_endpoint}
        :unreachable -> {:connection_unreachable, :check_questdb_endpoint}
        _other -> {:connection_failed, :check_questdb_endpoint}
      end

    %{
      probe_diagnostic_kind: kind,
      probe_diagnostic_stage: :connection_test,
      probe_remediation: remediation
    }
  end

  defp schema_diagnostic_metadata({:missing_columns, missing}) do
    %{
      probe_diagnostic_kind: :schema_mismatch,
      probe_diagnostic_stage: :schema_validation,
      probe_remediation: :run_questdb_schema_migration,
      probe_diagnostic_detail: "missing_columns:#{Enum.join(missing, ",")}"
    }
  end

  defp schema_diagnostic_metadata(reason) do
    {kind, remediation} =
      case reason_category(reason) do
        :authentication_failed -> {:authentication_failed, :check_schema_probe_credentials}
        :http_error -> {:schema_query_failed, :check_questdb_http_api}
        :timeout -> {:schema_query_timeout, :check_questdb_schema_access}
        :unreachable -> {:schema_unavailable, :check_questdb_schema_access}
        _other -> {:schema_unavailable, :check_questdb_schema_access}
      end

    %{
      probe_diagnostic_kind: kind,
      probe_diagnostic_stage: :schema_query,
      probe_remediation: remediation
    }
  end

  defp reason_category({:http_error, status, _body}) when status in [401, 403],
    do: :authentication_failed

  defp reason_category({:http_error, _status, _body}), do: :http_error
  defp reason_category(:econnrefused), do: :unreachable
  defp reason_category(:nxdomain), do: :unreachable
  defp reason_category(:timeout), do: :timeout

  defp reason_category(%{reason: reason}) when is_atom(reason),
    do: reason_category(reason)

  defp reason_category(reason) when is_exception(reason) do
    reason
    |> Exception.message()
    |> String.downcase()
    |> reason_category_from_text()
  end

  defp reason_category(reason) when is_binary(reason) do
    reason
    |> String.downcase()
    |> reason_category_from_text()
  end

  defp reason_category(reason) do
    reason
    |> inspect()
    |> String.downcase()
    |> reason_category_from_text()
  end

  defp reason_category_from_text(text) do
    cond do
      auth_error_text?(text) -> :authentication_failed
      timeout_text?(text) -> :timeout
      unreachable_text?(text) -> :unreachable
      http_error_text?(text) -> :http_error
      true -> :unknown
    end
  end

  defp auth_error_text?(text) do
    text =~ "401" or text =~ "403" or text =~ "unauthorized" or text =~ "forbidden"
  end

  defp timeout_text?(text), do: text =~ "timeout"

  defp unreachable_text?(text) do
    text =~ "econnrefused" or text =~ "nxdomain" or text =~ "closed"
  end

  defp http_error_text?(text), do: text =~ "http_error"

  defp probe_exec(sql, opts, policy) do
    exec_fun =
      Keyword.get(opts, :questdb_exec_fun) ||
        Map.fetch!(policy, :exec_fun)

    exec_fun.(sql, probe_opts(opts, policy))
  end

  defp probe_metadata(%DataSource{} = data_source, opts, policy) do
    %{
      adapter: "telemetry",
      storage: "questdb",
      data_source_id: data_source.data_source_id,
      http_endpoint: http_endpoint(opts, policy),
      connection_profile?: is_map(Keyword.get(opts, :source_connection_profile))
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp probe_opts(opts, policy) do
    [
      http_endpoint: http_endpoint(opts, policy),
      timeout: Keyword.get(opts, :questdb_timeout, Map.fetch!(policy, :timeout)),
      headers: auth_headers(opts)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == [] end)
  end

  defp auth_headers(opts) do
    material = Keyword.get(opts, :source_connection_material, [])
    headers = material |> Keyword.get(:headers, []) |> normalize_headers()

    cond do
      bearer_token = Keyword.get(material, :bearer_token) ->
        [{"authorization", "Bearer #{bearer_token}"} | headers]

      username = Keyword.get(material, :username) ->
        case Keyword.get(material, :password) do
          password when is_binary(password) ->
            encoded = Base.encode64("#{username}:#{password}")
            [{"authorization", "Basic #{encoded}"} | headers]

          _other ->
            headers
        end

      true ->
        headers
    end
  end

  defp normalize_headers(headers) when is_list(headers) do
    Enum.flat_map(headers, fn
      {key, value} -> [{to_string(key), to_string(value)}]
      _other -> []
    end)
  end

  defp normalize_headers(_headers), do: []

  defp http_endpoint(opts, policy) do
    Keyword.get(opts, :questdb_http_endpoint) ||
      opts
      |> Keyword.get(:source_connection_material, [])
      |> Keyword.get(:http_endpoint) ||
      opts
      |> Keyword.get(:source_connection_profile, %{})
      |> metadata_value(:http_endpoint) ||
      Map.get(policy, :http_endpoint)
  end

  defp probe_enabled?(opts, policy) do
    Keyword.get(opts, :questdb_probe?, Map.fetch!(policy, :enabled?))
  end

  defp metadata_value(metadata, key) when is_map(metadata) do
    Map.get(metadata, key, Map.get(metadata, Atom.to_string(key)))
  end

  defp metadata_value(_metadata, _key), do: nil
end
