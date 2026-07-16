defmodule Cadence.GroundNetworks.ProviderWebhookAuthenticator do
  @moduledoc "Capability-gated provider webhook authentication and common inbox boundary."

  alias Cadence.Contacts.ProviderClients.Registry
  alias Cadence.GroundNetworks.{ProviderAccountVersion, ProviderEventInbox}

  @default_body_byte_limit 262_144

  @type auth_context :: map()

  @callback authenticate(
              ProviderAccountVersion.t(),
              binary(),
              [{binary(), binary()}],
              binary(),
              keyword()
            ) :: {:ok, auth_context()} | {:error, term()}

  @callback normalize(binary(), auth_context(), keyword()) ::
              {:ok, [map()]} | {:error, term()}

  @spec ensure_enabled(ProviderAccountVersion.t(), keyword()) ::
          {:ok, module()} | {:error, term()}
  def ensure_enabled(%ProviderAccountVersion{} = version, opts \\ []) do
    with :ok <- ensure_webhook_mode(version.event_ingestion_mode),
         {:ok, authenticator} <- fetch_authenticator(version.provider_type, opts),
         :ok <- validate_authenticator(authenticator) do
      {:ok, authenticator}
    end
  end

  @spec authenticate_and_ingest(
          ProviderAccountVersion.t(),
          binary(),
          [{binary(), binary()}],
          binary(),
          keyword()
        ) :: {:ok, ProviderEventInbox.ingest_summary()} | {:error, term()}
  def authenticate_and_ingest(version, endpoint_ref, headers, raw_body, opts \\ [])
      when is_binary(endpoint_ref) and is_list(headers) and is_binary(raw_body) do
    with {:ok, authenticator} <- ensure_enabled(version, opts),
         :ok <- validate_body_size(raw_body, opts),
         {:ok, auth_context} <-
           authenticator.authenticate(version, endpoint_ref, headers, raw_body, opts),
         {:ok, deliveries} <- authenticator.normalize(raw_body, auth_context, opts),
         true <- is_list(deliveries),
         {:ok, summary} <-
           ProviderEventInbox.ingest_delivery(
             version,
             version.environment_ref,
             endpoint_ref,
             deliveries,
             opts
           ) do
      {:ok, summary}
    else
      false -> {:error, :provider_webhook_normalization_invalid}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_authenticator(provider_type, opts) do
    case Keyword.get(opts, :authenticator_registry) do
      registry when is_function(registry, 1) -> registry.(provider_type)
      _other -> Registry.fetch_webhook_authenticator(provider_type)
    end
  end

  defp validate_authenticator(module) when is_atom(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :authenticate, 5) and
         function_exported?(module, :normalize, 3),
       do: :ok,
       else: {:error, :provider_webhook_authenticator_invalid}
  end

  defp validate_authenticator(_module), do: {:error, :provider_webhook_authenticator_invalid}

  defp ensure_webhook_mode(mode) when mode in [:webhook, :hybrid], do: :ok
  defp ensure_webhook_mode(_mode), do: {:error, :provider_webhook_ingestion_disabled}

  defp validate_body_size(body, opts) do
    limit = Keyword.get(opts, :body_byte_limit, @default_body_byte_limit)
    if byte_size(body) <= limit, do: :ok, else: {:error, :provider_webhook_body_too_large}
  end
end
