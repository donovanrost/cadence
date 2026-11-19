defmodule Cadence.Reads.Comms.ProviderHealth do
  @moduledoc """
  A mission provider's last validate and sync for the console (L12), from the provider's own
  record (`metadata.control_plane`, `metadata.sync`): `{status: "healthy" | "failed" | nil,
  checked_at, error}`, where `error` is a sentence for a person, never the raw provider evidence.
  """

  @messages %{
    "authentication_failed" => "The provider refused the account's credential.",
    "authorization_failed" => "The provider says this account isn't allowed to do that.",
    "unsupported_capability" => "The provider doesn't support this.",
    "provider_unavailable" => "The provider couldn't be reached.",
    "known_timeout" => "The provider didn't answer in time.",
    "rate_limited" => "The provider is limiting requests. Try again shortly.",
    "malformed_response" => "The provider's answer couldn't be read.",
    "ambiguous_outcome" => "The provider's answer was unclear. Try again."
  }

  @spec of(struct()) :: %{validate: map(), sync: map()}
  def of(provider) do
    metadata = provider.metadata || %{}

    %{
      validate: observation(metadata["control_plane"]),
      sync: observation(metadata["sync"])
    }
  end

  @doc "The sentence for a recorded failure."
  @spec message(term()) :: binary()
  def message(%{"category" => category}) when is_map_key(@messages, category),
    do: Map.fetch!(@messages, category)

  def message(%{"category" => "invalid_request", "detail" => detail}) when is_binary(detail),
    do: "The provider refused the request: #{detail}."

  def message(_error), do: "The provider check failed."

  defp observation(%{"status" => status} = observed) when status in ["healthy", "failed"] do
    %{
      status: status,
      checked_at: observed["checked_at"],
      error: if(status == "failed", do: message(observed["error"]))
    }
  end

  defp observation(_never), do: %{status: nil, checked_at: nil, error: nil}
end
