defmodule Cadence.Applications.ActionProviderRegistry do
  @moduledoc "Generic bounded registry for application-owned action providers."

  @max_providers 16
  @contributors [
    Cadence.Applications.TelemetryDecom,
    Cadence.Applications.DerivedTelemetry,
    Cadence.Applications.Limits
  ]

  @spec providers() :: %{optional(binary()) => module()}
  def providers do
    if length(@contributors) <= @max_providers,
      do: build_provider_map(),
      else: %{}
  end

  defp build_provider_map do
    Enum.reduce_while(@contributors, %{}, fn contributor, acc ->
      put_provider(acc, contributor.application_key(), contributor.action_provider())
    end)
  end

  defp put_provider(acc, application_key, provider) do
    if is_binary(application_key) and is_atom(provider) and
         not Map.has_key?(acc, application_key),
       do: {:cont, Map.put(acc, application_key, provider)},
       else: {:halt, %{}}
  end

  @spec fetch(binary()) :: {:ok, module()} | {:error, :unknown_application_action_provider}
  def fetch(application_key) when is_binary(application_key) do
    case Map.fetch(providers(), application_key) do
      {:ok, provider} when is_atom(provider) ->
        if Code.ensure_loaded?(provider) and function_exported?(provider, :execute, 3),
          do: {:ok, provider},
          else: {:error, :unknown_application_action_provider}

      _other ->
        {:error, :unknown_application_action_provider}
    end
  end

  def fetch(_application_key), do: {:error, :unknown_application_action_provider}
end
