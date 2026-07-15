defmodule Cadence.GroundNetworks.DeliveryDescriptor do
  @moduledoc "Validated contact-scoped delivery descriptor."

  alias Cadence.GroundNetworks.Validation

  @statuses %{
    "pending" => :pending,
    "ready" => :ready,
    "connected" => :connected,
    "flowing" => :flowing,
    "degraded" => :degraded,
    "failed" => :failed,
    "ended" => :ended
  }
  @directions %{"downlink" => :downlink, "uplink" => :uplink, "bidirectional" => :bidirectional}

  @type t :: %__MODULE__{
          status: atom(),
          direction: atom(),
          delivery_kind: binary(),
          mode: binary(),
          protocol: binary(),
          endpoint_ref: binary(),
          framing: map(),
          allowed_source_refs: [binary()],
          activation_window: map(),
          credential_ref: binary() | nil,
          diagnostics: map(),
          reason: binary() | nil,
          evidence: map()
        }

  defstruct [
    :status,
    :direction,
    :delivery_kind,
    :mode,
    :protocol,
    :endpoint_ref,
    :credential_ref,
    :reason,
    framing: %{},
    allowed_source_refs: [],
    activation_window: %{},
    diagnostics: %{},
    evidence: %{}
  ]

  @spec from_external(map()) :: {:ok, t()} | {:error, term()}
  def from_external(descriptor) when is_map(descriptor) do
    descriptor = Validation.sanitize(descriptor)

    with {:ok, status} <- Validation.member(descriptor, "status", @statuses),
         {:ok, direction} <- Validation.member(descriptor, "direction", @directions),
         {:ok, delivery_kind} <- Validation.required_string(descriptor, "delivery_kind"),
         {:ok, mode} <- Validation.required_string(descriptor, "mode"),
         {:ok, protocol} <- Validation.required_string(descriptor, "protocol"),
         {:ok, endpoint_ref} <- Validation.required_string(descriptor, "endpoint_ref"),
         {:ok, framing} <- Validation.object(descriptor, "framing"),
         {:ok, source_refs} <- Validation.string_list(descriptor, "allowed_source_refs"),
         {:ok, activation_window} <- Validation.object(descriptor, "activation_window"),
         {:ok, _starts_at} <- Validation.datetime(activation_window, "starts_at"),
         {:ok, _ends_at} <- Validation.datetime(activation_window, "ends_at"),
         {:ok, credential_ref} <- Validation.optional_string(descriptor, "credential_ref"),
         {:ok, diagnostics} <- Validation.object(descriptor, "diagnostics"),
         {:ok, reason} <- Validation.optional_string(descriptor, "reason") do
      {:ok,
       %__MODULE__{
         status: status,
         direction: direction,
         delivery_kind: delivery_kind,
         mode: mode,
         protocol: protocol,
         endpoint_ref: endpoint_ref,
         framing: framing,
         allowed_source_refs: source_refs,
         activation_window: activation_window,
         credential_ref: credential_ref,
         diagnostics: diagnostics,
         reason: reason,
         evidence: descriptor
       }}
    end
  end

  def from_external(_descriptor), do: Validation.malformed(:delivery_descriptor)

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = descriptor) do
    descriptor.evidence
  end
end
