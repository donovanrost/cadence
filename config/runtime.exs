import Config

bootstrap_admin_enabled? =
  System.get_env("CADENCE_BOOTSTRAP_ADMIN_ENABLED", "false")
  |> String.downcase()
  |> then(&(&1 in ["1", "true", "yes", "on"]))

if bootstrap_admin_enabled? do
  config :cadence, :bootstrap_admin,
    enabled: true,
    user_id: System.get_env("CADENCE_BOOTSTRAP_ADMIN_USER_ID", "user_bootstrap_admin"),
    email:
      System.get_env("CADENCE_BOOTSTRAP_ADMIN_EMAIL") ||
        raise("CADENCE_BOOTSTRAP_ADMIN_EMAIL is required when bootstrap admin is enabled"),
    display_name: System.get_env("CADENCE_BOOTSTRAP_ADMIN_DISPLAY_NAME", "Bootstrap Admin"),
    password:
      System.get_env("CADENCE_BOOTSTRAP_ADMIN_PASSWORD") ||
        raise("CADENCE_BOOTSTRAP_ADMIN_PASSWORD is required when bootstrap admin is enabled"),
    session_ttl_seconds:
      System.get_env("CADENCE_BOOTSTRAP_ADMIN_SESSION_TTL_SECONDS", "86400")
      |> String.to_integer()
end

case System.get_env("CADENCE_DASHBOARD_SOURCE_CREDENTIAL_ENV_PROFILES") do
  nil ->
    :ok

  encoded_profiles ->
    case Jason.decode(encoded_profiles) do
      {:ok, profiles} when is_map(profiles) ->
        current_config = Application.get_env(:cadence, :dashboard_source_credentials, [])

        config :cadence,
               :dashboard_source_credentials,
               Keyword.merge(current_config,
                 material_resolver:
                   {Cadence.Dashboards.SourceCredentials.SecretMaterialResolver, :resolve},
                 secret_backend:
                   {Cadence.Dashboards.SourceCredentials.EnvSecretBackend, :fetch_material},
                 env_material_profiles: profiles
               )

      {:ok, _other} ->
        raise "CADENCE_DASHBOARD_SOURCE_CREDENTIAL_ENV_PROFILES must decode to a JSON object"

      {:error, reason} ->
        raise "CADENCE_DASHBOARD_SOURCE_CREDENTIAL_ENV_PROFILES is invalid JSON: #{inspect(reason)}"
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
