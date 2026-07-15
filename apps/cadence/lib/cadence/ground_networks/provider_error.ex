defmodule Cadence.GroundNetworks.ProviderError do
  @moduledoc "Structured provider failure classification used by every adapter."

  alias Cadence.GroundNetworks.Validation

  @categories %{
    "invalid_request" => :invalid_request,
    "authentication_failed" => :authentication_failed,
    "authorization_failed" => :authorization_failed,
    "unsupported_capability" => :unsupported_capability,
    "not_found" => :not_found,
    "conflict" => :conflict,
    "no_capacity" => :no_capacity,
    "rate_limited" => :rate_limited,
    "provider_unavailable" => :provider_unavailable,
    "known_timeout" => :known_timeout,
    "ambiguous_outcome" => :ambiguous_outcome,
    "malformed_response" => :malformed_response
  }

  @type category :: atom()
  @type t :: %__MODULE__{
          category: category(),
          detail: binary(),
          retryable: boolean(),
          retry_after_seconds: non_neg_integer() | nil,
          provider_request_ref: binary() | nil,
          http_status: non_neg_integer() | nil,
          evidence: map()
        }

  defstruct [
    :category,
    :detail,
    :retry_after_seconds,
    :provider_request_ref,
    :http_status,
    retryable: false,
    evidence: %{}
  ]

  @spec from_response(non_neg_integer(), term()) :: t()
  def from_response(status, body) do
    evidence = sanitize(body)
    error = if is_map(body), do: Map.get(body, "error", %{}), else: %{}

    %__MODULE__{
      category: Map.get(@categories, error["code"], fallback_category(status)),
      detail: error["detail"] || "provider request failed with HTTP #{status}",
      retryable: Map.get(error, "retryable", status == 429 or status >= 500),
      retry_after_seconds: error["retry_after_seconds"],
      provider_request_ref: error["provider_request_ref"],
      http_status: status,
      evidence: evidence
    }
  end

  @spec unavailable(term()) :: t()
  def unavailable(reason) do
    %__MODULE__{
      category: :provider_unavailable,
      detail: "provider request was not sent",
      retryable: true,
      evidence: sanitize(reason)
    }
  end

  @spec ambiguous(term()) :: t()
  def ambiguous(reason) do
    %__MODULE__{
      category: :ambiguous_outcome,
      detail: "provider request outcome is unknown",
      retryable: false,
      evidence: sanitize(reason)
    }
  end

  @spec malformed(term()) :: t()
  def malformed(reason) do
    %__MODULE__{
      category: :malformed_response,
      detail: "provider response did not match the declared contract",
      retryable: false,
      evidence: sanitize(reason)
    }
  end

  @spec invalid(binary(), term()) :: t()
  def invalid(detail, evidence \\ %{}) do
    %__MODULE__{
      category: :invalid_request,
      detail: detail,
      retryable: false,
      evidence: sanitize(evidence)
    }
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = error) do
    %{
      "category" => Atom.to_string(error.category),
      "detail" => error.detail,
      "retryable" => error.retryable,
      "retry_after_seconds" => error.retry_after_seconds,
      "provider_request_ref" => error.provider_request_ref,
      "http_status" => error.http_status,
      "evidence" => error.evidence
    }
  end

  defp fallback_category(401), do: :authentication_failed
  defp fallback_category(403), do: :authorization_failed
  defp fallback_category(404), do: :not_found
  defp fallback_category(409), do: :conflict
  defp fallback_category(422), do: :invalid_request
  defp fallback_category(429), do: :rate_limited
  defp fallback_category(status) when status >= 500, do: :provider_unavailable
  defp fallback_category(_status), do: :provider_error

  defp sanitize(value), do: Validation.sanitize(value)
end
