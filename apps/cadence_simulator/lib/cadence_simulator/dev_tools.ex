defmodule CadenceSimulator.DevTools do
  @moduledoc """
  Shared helpers for profile-driven local developer tooling.
  """

  alias Cadence.DevProfile
  alias CadenceSimulator.{CadenceRuntimeBootstrap, CLI, SimulatorContactBootstrap}

  @type profile_runtime :: %{
          profile: Cadence.DevProfile.t(),
          bootstrap_summary: map(),
          runtime_opts: keyword()
        }

  @spec resolve_profile_runtime(String.t(), [String.t()], keyword()) ::
          {:ok, profile_runtime()} | {:help, String.t()} | {:error, String.t() | term()}
  def resolve_profile_runtime(profile_identifier, simulator_args, opts \\ [])
      when is_binary(profile_identifier) and is_list(simulator_args) and is_list(opts) do
    expected_runtime_mode = Keyword.get(opts, :runtime_mode)
    bootstrap_run_opts = Keyword.take(opts, [:req_client, :print_summary?])
    runtime_bootstrap_opts = Keyword.take(opts, [:http_client])

    with {:ok, profile} <- DevProfile.load(profile_identifier),
         {:ok, bootstrap_summary} <- run_bootstrap(profile, bootstrap_run_opts),
         {:ok, parsed_runtime_opts} <-
           parse_profile_runtime_opts(profile, simulator_args, expected_runtime_mode),
         {:ok, resolved_runtime_opts} <-
           CadenceRuntimeBootstrap.resolve_runtime_opts(
             apply_bootstrap_summary(parsed_runtime_opts, profile, bootstrap_summary),
             runtime_bootstrap_opts
           ) do
      {:ok,
       %{
         profile: profile,
         bootstrap_summary: bootstrap_summary,
         runtime_opts: resolved_runtime_opts
       }}
    end
  end

  @spec profiler_defaults(String.t()) ::
          {:ok,
           %{
             profile: Cadence.DevProfile.t(),
             node: String.t() | nil,
             mission_id: String.t() | nil
           }}
          | {:error, String.t()}
  def profiler_defaults(profile_identifier) when is_binary(profile_identifier) do
    with {:ok, profile} <- DevProfile.load(profile_identifier) do
      defaults = DevProfile.profiler_defaults(profile)
      {:ok, %{profile: profile, node: defaults.node, mission_id: defaults.mission_id}}
    end
  end

  defp run_bootstrap(profile, bootstrap_run_opts) do
    summary =
      SimulatorContactBootstrap.run(
        DevProfile.bootstrap_config(profile),
        Keyword.put_new(bootstrap_run_opts, :print_summary?, false)
      )

    {:ok, summary}
  rescue
    exception ->
      {:error, Exception.message(exception)}
  end

  defp parse_profile_runtime_opts(profile, simulator_args, expected_runtime_mode) do
    cli_args = ["--config", DevProfile.simulator_config_path(profile) | simulator_args]

    case CLI.parse_args(cli_args) do
      {:ok, opts} ->
        runtime_mode = opts[:runtime_mode]

        if is_nil(expected_runtime_mode) or runtime_mode == expected_runtime_mode do
          {:ok, DevProfile.resolve_runtime_opts(profile, opts)}
        else
          {:error,
           "profile #{profile.name} resolves to #{inspect(runtime_mode)} mode, " <>
             "but #{inspect(expected_runtime_mode)} is required"}
        end

      {:help, usage} ->
        {:help, usage}

      {:error, message} ->
        {:error, message}
    end
  end

  defp apply_bootstrap_summary(runtime_opts, profile, bootstrap_summary) do
    bootstrap = DevProfile.bootstrap_config(profile)
    effective_config = Map.get(bootstrap_summary, :effective_config, %{})

    runtime_opts
    |> put_new_opt(:cadence_url, bootstrap["base_url"])
    |> put_new_opt(:api_token, bootstrap_summary.api_token)
    |> put_new_opt(:organization_id, bootstrap_summary.organization_id)
    |> put_new_opt(:mission_id, bootstrap_summary.mission_id)
    |> put_new_opt(
      :realized_contact_id,
      get_in(bootstrap_summary, [:realized_contact, "realized_contact_id"])
    )
    |> put_new_opt(
      :path_id,
      bootstrap["downlink_path_id"] ||
        bootstrap["uplink_path_id"] ||
        Map.get(effective_config, :downlink_path_id) ||
        Map.get(effective_config, :uplink_path_id)
    )
  end

  defp put_new_opt(opts, _key, nil), do: opts

  defp put_new_opt(opts, key, value) when is_list(opts) and is_atom(key) do
    Keyword.put_new(opts, key, value)
  end
end
