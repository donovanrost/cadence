defmodule Cadence.Applications.ActionProviderRegistry do
  @moduledoc "Generic bounded registry for application-owned action providers."

  alias Cadence.Applications.JSONBoundary

  @max_providers 16
  @optional_contributors [CadenceWeb.ApplicationContributions.OrganizationAdmin]

  @compile {:no_warn_undefined,
            {CadenceWeb.ApplicationContributions.OrganizationAdmin, :application_key, 0}}
  @compile {:no_warn_undefined,
            {CadenceWeb.ApplicationContributions.OrganizationAdmin, :action_provider, 0}}
  @contributors [
    Cadence.Applications.Comms,
    Cadence.Applications.Spacecraft,
    Cadence.Applications.TelemetryDecom,
    Cadence.Applications.DerivedTelemetry,
    Cadence.Applications.Limits,
    Cadence.Applications.MissionCatalog,
    Cadence.Applications.OpsConsole
  ]

  @spec providers() :: %{optional(binary()) => module()}
  def providers do
    core_providers = providers(@contributors)

    case providers(optional_contributors()) do
      optional_providers when is_map(optional_providers) ->
        Map.merge(core_providers, optional_providers)
    end
  end

  @doc false
  @spec providers([module()]) :: %{optional(binary()) => module()}
  def providers(contributors) when is_list(contributors) do
    with true <- length(contributors) <= @max_providers,
         {:ok, entries} <- collect_entries(contributors),
         true <- length(entries) <= @max_providers,
         true <- unique?(Enum.map(entries, & &1.application_key)) do
      Map.new(entries, fn entry -> {entry.application_key, entry.provider} end)
    else
      _invalid -> %{}
    end
  end

  def providers(_contributors), do: %{}

  @spec validate(map()) :: :ok | {:error, :invalid_application_action_provider_registry}
  def validate(registered_providers) when is_map(registered_providers) do
    if valid_registered_providers?(registered_providers),
      do: :ok,
      else: {:error, :invalid_application_action_provider_registry}
  end

  def validate(_registered_providers),
    do: {:error, :invalid_application_action_provider_registry}

  @spec fetch(binary()) :: {:ok, module()} | {:error, :unknown_application_action_provider}
  def fetch(application_key) when is_binary(application_key) do
    case Map.fetch(providers(), application_key) do
      {:ok, provider} when is_atom(provider) ->
        provider_for_application(provider, application_key)

      _missing ->
        {:error, :unknown_application_action_provider}
    end
  end

  def fetch(_application_key), do: {:error, :unknown_application_action_provider}

  @doc false
  @spec fetch(binary(), %{optional(binary()) => module()}) ::
          {:ok, module()} | {:error, :unknown_application_action_provider}
  def fetch(application_key, registered_providers)
      when is_binary(application_key) and is_map(registered_providers) do
    if valid_registered_providers?(registered_providers) do
      case Map.fetch(registered_providers, application_key) do
        {:ok, provider} when is_atom(provider) ->
          provider_for_application(provider, application_key)

        _missing ->
          {:error, :unknown_application_action_provider}
      end
    else
      {:error, :unknown_application_action_provider}
    end
  end

  def fetch(_application_key, _registered_providers),
    do: {:error, :unknown_application_action_provider}

  defp provider_for_application(provider, application_key) do
    if valid_provider?(provider) and provider_matches_application_key?(provider, application_key),
      do: {:ok, provider},
      else: {:error, :unknown_application_action_provider}
  end

  defp collect_entries(contributors) do
    Enum.reduce_while(contributors, {:ok, []}, fn contributor, {:ok, acc} ->
      case contributor_entry(contributor) do
        {:ok, entry} -> {:cont, {:ok, [entry | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp contributor_entry(contributor) when is_atom(contributor) do
    with true <- Code.ensure_loaded?(contributor),
         true <- function_exported?(contributor, :application_key, 0),
         true <- function_exported?(contributor, :action_provider, 0),
         {:ok, application_key} <- safe_apply(contributor, :application_key, []),
         {:ok, provider} <- safe_apply(contributor, :action_provider, []),
         true <- valid_application_key?(application_key),
         true <- valid_provider?(provider),
         true <- provider_identity?(provider, application_key) do
      {:ok, %{application_key: application_key, provider: provider}}
    else
      _invalid -> {:error, :invalid_application_action_provider_registry}
    end
  end

  defp contributor_entry(_contributor),
    do: {:error, :invalid_application_action_provider_registry}

  defp optional_contributors do
    Enum.filter(@optional_contributors, &Code.ensure_loaded?/1)
  end

  defp valid_provider?(provider) when is_atom(provider) do
    Code.ensure_loaded?(provider) and function_exported?(provider, :application_key, 0) and
      function_exported?(provider, :execute, 3)
  end

  defp valid_provider?(_provider), do: false

  defp provider_identity?(provider, application_key) do
    function_exported?(provider, :application_key, 0) and
      case safe_apply(provider, :application_key, []) do
        {:ok, ^application_key} -> true
        _invalid -> false
      end
  end

  defp provider_matches_application_key?(provider, application_key) do
    case safe_apply(provider, :application_key, []) do
      {:ok, ^application_key} -> true
      _invalid -> false
    end
  end

  defp valid_application_key?(value) when is_binary(value) and value != "" do
    JSONBoundary.validate(value) == :ok
  end

  defp valid_application_key?(_value), do: false

  defp unique?(values), do: length(values) == length(Enum.uniq(values))

  defp valid_registered_providers?(registered_providers)
       when is_map(registered_providers) and map_size(registered_providers) <= @max_providers do
    entries = Map.to_list(registered_providers)

    Enum.all?(entries, fn {application_key, provider} ->
      valid_application_key?(application_key) and valid_provider?(provider) and
        provider_matches_application_key?(provider, application_key)
    end)
  end

  defp valid_registered_providers?(_registered_providers), do: false

  defp safe_apply(module, function, arguments) do
    {:ok, apply(module, function, arguments)}
  rescue
    _exception -> {:error, :provider_exception}
  catch
    _kind, _value -> {:error, :provider_exception}
  end
end
