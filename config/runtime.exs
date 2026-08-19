import Config

case System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT") do
  endpoint when is_binary(endpoint) and endpoint != "" ->
    config :opentelemetry,
      span_processor: :batch,
      traces_exporter: :otlp

    config :opentelemetry_exporter,
      otlp_protocol: :http_protobuf,
      otlp_endpoint: endpoint

  _unset_or_empty ->
    :ok
end

parse_positive_integer = fn name, default ->
  case Integer.parse(System.get_env(name, "")) do
    {value, ""} when value > 0 -> value
    _unset_or_invalid -> default
  end
end

journal_path = System.get_env("CADENCE_INGRESS_JOURNAL_PATH")
journal_enabled = System.get_env("CADENCE_INGRESS_JOURNAL_ENABLED")

if config_env() == :prod or (is_binary(journal_path) and journal_path != "") or
     (is_binary(journal_enabled) and journal_enabled != "") do
  enabled? =
    case journal_enabled || "false" do
      value when value in ["true", "1"] -> true
      value when value in ["false", "0"] -> false
      invalid -> raise "invalid CADENCE_INGRESS_JOURNAL_ENABLED: #{inspect(invalid)}"
    end

  durability =
    case System.get_env("CADENCE_INGRESS_JOURNAL_DURABILITY", "sync") do
      "sync" -> :sync
      "page_cache" -> :page_cache
      invalid -> raise "invalid CADENCE_INGRESS_JOURNAL_DURABILITY: #{inspect(invalid)}"
    end

  config :cadence, :ingress_journal,
    enabled?: enabled?,
    base_path: journal_path || "/var/lib/cadence/ingress_journal",
    max_bytes: parse_positive_integer.("CADENCE_INGRESS_JOURNAL_MAX_BYTES", 8_589_934_592),
    segment_bytes: parse_positive_integer.("CADENCE_INGRESS_JOURNAL_SEGMENT_BYTES", 268_435_456),
    capture_record_bytes:
      parse_positive_integer.("CADENCE_INGRESS_JOURNAL_CAPTURE_RECORD_BYTES", 262_144),
    processing_max_batch_entries:
      parse_positive_integer.("CADENCE_INGRESS_JOURNAL_PROCESSING_MAX_BATCH_ENTRIES", 8),
    processing_max_batch_bytes:
      parse_positive_integer.("CADENCE_INGRESS_JOURNAL_PROCESSING_MAX_BATCH_BYTES", 2_097_152),
    durability: durability,
    checkpoint_interval_ms:
      parse_positive_integer.("CADENCE_INGRESS_JOURNAL_CHECKPOINT_INTERVAL_MS", 250),
    consumers: [:processing, :archive]
end

parse_headers = fn encoded_headers ->
  encoded_headers
  |> to_string()
  |> String.split(",", trim: true)
  |> Enum.flat_map(fn encoded_header ->
    case String.split(encoded_header, "=", parts: 2) do
      [key, value] when key != "" -> [{URI.decode(key), URI.decode(value)}]
      _invalid -> []
    end
  end)
end

metrics_endpoint =
  case System.get_env("OTEL_EXPORTER_OTLP_METRICS_ENDPOINT") do
    endpoint when is_binary(endpoint) and endpoint != "" ->
      endpoint

    _unset_or_empty ->
      case System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT") do
        endpoint when is_binary(endpoint) and endpoint != "" ->
          String.trim_trailing(endpoint, "/") <> "/v1/metrics"

        _unset_or_empty ->
          nil
      end
  end

if config_env() != :test and is_binary(metrics_endpoint) do
  headers =
    System.get_env("OTEL_EXPORTER_OTLP_METRICS_HEADERS") ||
      System.get_env("OTEL_EXPORTER_OTLP_HEADERS") ||
      ""

  config :cadence, :otel_metrics,
    enabled: true,
    endpoint: metrics_endpoint,
    headers: parse_headers.(headers),
    export_interval_ms:
      parse_positive_integer.("CADENCE_OTEL_METRICS_EXPORT_INTERVAL_MS", 10_000),
    sample_interval_ms:
      parse_positive_integer.("CADENCE_OTEL_METRICS_SAMPLE_INTERVAL_MS", 10_000),
    mission_health_interval_ms:
      parse_positive_integer.("CADENCE_OTEL_MISSION_HEALTH_INTERVAL_MS", 15_000),
    freshness_grace_seconds:
      parse_positive_integer.("CADENCE_TELEMETRY_FRESHNESS_GRACE_SECONDS", 30),
    max_queue: parse_positive_integer.("CADENCE_OTEL_METRICS_MAX_QUEUE", 10_000),
    max_series: parse_positive_integer.("CADENCE_OTEL_METRICS_MAX_SERIES", 5_000),
    timeout_ms: parse_positive_integer.("OTEL_EXPORTER_OTLP_METRICS_TIMEOUT", 5_000)
end

logs_endpoint =
  case System.get_env("OTEL_EXPORTER_OTLP_LOGS_ENDPOINT") do
    endpoint when is_binary(endpoint) and endpoint != "" ->
      endpoint

    _unset_or_empty ->
      case System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT") do
        endpoint when is_binary(endpoint) and endpoint != "" ->
          String.trim_trailing(endpoint, "/") <> "/v1/logs"

        _unset_or_empty ->
          nil
      end
  end

if config_env() != :test and is_binary(logs_endpoint) do
  log_level =
    case System.get_env("CADENCE_OTEL_LOG_LEVEL", "info") |> String.downcase() do
      "debug" -> :debug
      "notice" -> :notice
      "warning" -> :warning
      "error" -> :error
      "critical" -> :critical
      "alert" -> :alert
      "emergency" -> :emergency
      _info_or_invalid -> :info
    end

  headers =
    System.get_env("OTEL_EXPORTER_OTLP_LOGS_HEADERS") ||
      System.get_env("OTEL_EXPORTER_OTLP_HEADERS") ||
      ""

  config :cadence, :otel_logs,
    enabled: true,
    endpoint: logs_endpoint,
    headers: parse_headers.(headers),
    level: log_level,
    batch_size: parse_positive_integer.("CADENCE_OTEL_LOG_BATCH_SIZE", 100),
    flush_interval_ms: parse_positive_integer.("CADENCE_OTEL_LOG_FLUSH_INTERVAL_MS", 1_000),
    max_queue: parse_positive_integer.("CADENCE_OTEL_LOG_MAX_QUEUE", 5_000),
    timeout_ms: parse_positive_integer.("OTEL_EXPORTER_OTLP_LOGS_TIMEOUT", 5_000)
end

admin_email = System.get_env("CADENCE_ADMIN_EMAIL")
admin_password = System.get_env("CADENCE_ADMIN_PASSWORD")

case {admin_email, admin_password} do
  {nil, nil} ->
    config :cadence, :environment_admin, enabled: false

  {email, password}
  when is_binary(email) and email != "" and is_binary(password) and password != "" ->
    config :cadence, :environment_admin,
      enabled: true,
      email: email,
      display_name: System.get_env("CADENCE_ADMIN_DISPLAY_NAME", "Cadence Administrator"),
      password: password

  _partial_configuration ->
    raise("CADENCE_ADMIN_EMAIL and CADENCE_ADMIN_PASSWORD must be set together")
end

config :cadence_web,
       :admin_mode_ttl_seconds,
       System.get_env("CADENCE_ADMIN_MODE_TTL_SECONDS", "3600") |> String.to_integer()

case System.get_env("CADENCE_TELEMETRY_CURRENT_VALUE_STORE", "ets") |> String.downcase() do
  "postgres" ->
    config :cadence, :telemetry_current_value_store,
      module: Cadence.Telemetry.CurrentValueStore.Postgres

  _other ->
    :ok
end

case System.get_env("CADENCE_DATA_SOURCE_CREDENTIAL_ENV_PROFILES") ||
       System.get_env("CADENCE_DASHBOARD_SOURCE_CREDENTIAL_ENV_PROFILES") do
  nil ->
    :ok

  encoded_profiles ->
    case Jason.decode(encoded_profiles) do
      {:ok, profiles} when is_map(profiles) ->
        config :cadence,
               :data_source_credentials,
               material_resolver:
                 {Cadence.Management.DataSources.Credentials.SecretMaterialResolver, :resolve},
               secret_backend:
                 {Cadence.Management.DataSources.Credentials.EnvSecretBackend, :fetch_material},
               env_material_profiles: profiles

      {:ok, _other} ->
        raise "CADENCE_DATA_SOURCE_CREDENTIAL_ENV_PROFILES must decode to a JSON object"

      {:error, reason} ->
        raise "CADENCE_DATA_SOURCE_CREDENTIAL_ENV_PROFILES is invalid JSON: #{inspect(reason)}"
    end
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      Expected a PostgreSQL connection URL for Cadence.Repo.
      """

  pool_size =
    System.get_env("POOL_SIZE", "10")
    |> String.to_integer()

  config :cadence, Cadence.Repo,
    url: database_url,
    pool_size: pool_size

  host = System.get_env("PHX_HOST") || "example.com"

  port =
    System.get_env("PORT", "4001")
    |> String.to_integer()

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      Generate one with: mix phx.gen.secret
      """

  config :cadence_web, CadenceWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base,
    server: true
end
