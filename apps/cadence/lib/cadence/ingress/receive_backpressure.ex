defmodule Cadence.Ingress.ReceiveBackpressure do
  @moduledoc """
  What a receiver does when its bounded buffer (the ingress journal, or the executor queue
  without one) is full (DECISIONS #83). Never a silent drop:

  - a transport that can push back (`push_back?: true`; TCP) **pauses**: it stops reading, flow
    control holds the sender, nothing is lost and only stamps beyond the buffer arrive late.
    Counted as `[:cadence, :ingress, :reads_paused]` when the pause begins;
  - a transport that can't (`push_back?: false`; UDP and the like) **drops** the frame, counted as
    `[:cadence, :ingress, :frames_dropped]` with its bytes.

  No adapter passes `false` today (`tcp_socket` is the only one); the drop path exists so the
  first non-push-back adapter can't drop silently.
  """

  @paused [:cadence, :ingress, :reads_paused]
  @dropped [:cadence, :ingress, :frames_dropped]

  @type metadata :: %{
          optional(:mission_id) => binary() | nil,
          optional(:realized_contact_id) => binary() | nil,
          optional(:provider_binding_id) => binary() | nil,
          optional(:buffer) => :journal | :executor
        }

  @doc "Decides and counts. `bytes` is the size of what couldn't be admitted."
  @spec on_full(boolean(), metadata(), non_neg_integer()) :: :pause | :drop
  def on_full(push_back?, metadata, bytes)

  def on_full(true, metadata, bytes) when is_map(metadata) and is_integer(bytes) do
    :telemetry.execute(@paused, %{count: 1, bytes: bytes}, metadata)
    :pause
  end

  def on_full(false, metadata, bytes) when is_map(metadata) and is_integer(bytes) do
    :telemetry.execute(@dropped, %{count: 1, bytes: bytes}, metadata)
    :drop
  end

  @doc false
  def paused_event, do: @paused

  @doc false
  def dropped_event, do: @dropped
end
