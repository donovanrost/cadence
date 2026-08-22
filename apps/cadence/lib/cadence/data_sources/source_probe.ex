defmodule Cadence.DataSources.SourceProbe do
  @moduledoc """
  Normalized result from a physical source probe.

  Descriptor checks and adapter-backed IO checks both collapse into this shape
  before Cadence records a source health event.
  """

  @type health :: :healthy | :degraded | :unavailable | :unknown

  @type t :: %__MODULE__{
          source_health: health(),
          reason: atom() | binary(),
          probe_kind: atom(),
          message: binary() | nil,
          metadata: map()
        }

  defstruct source_health: :healthy,
            reason: :source_probe_succeeded,
            probe_kind: :descriptor,
            message: nil,
            metadata: %{}

  @spec healthy(atom() | binary(), map(), keyword()) :: t()
  def healthy(reason \\ :source_probe_succeeded, metadata \\ %{}, opts \\ []) do
    new(:healthy, reason, metadata, opts)
  end

  @spec degraded(atom() | binary(), map(), keyword()) :: t()
  def degraded(reason, metadata \\ %{}, opts \\ []) do
    new(:degraded, reason, metadata, opts)
  end

  @spec unavailable(atom() | binary(), map(), keyword()) :: t()
  def unavailable(reason, metadata \\ %{}, opts \\ []) do
    new(:unavailable, reason, metadata, opts)
  end

  @spec unsupported(map()) :: t()
  def unsupported(metadata \\ %{}) do
    healthy(:source_adapter_probe_unsupported, metadata, probe_kind: :adapter_unsupported)
  end

  @spec normalize(term()) :: t()
  def normalize(%__MODULE__{} = probe), do: probe
  def normalize(:ok), do: healthy(:source_probe_succeeded, %{}, probe_kind: :adapter)
  def normalize({:ok, %__MODULE__{} = probe}), do: probe

  def normalize({:ok, metadata}) when is_map(metadata) do
    healthy(:source_probe_succeeded, metadata, probe_kind: :adapter)
  end

  def normalize({:healthy, reason}) do
    healthy(reason, %{}, probe_kind: :adapter)
  end

  def normalize({:healthy, reason, metadata}) when is_map(metadata) do
    healthy(reason, metadata, probe_kind: :adapter)
  end

  def normalize({:degraded, reason}) do
    degraded(reason, %{}, probe_kind: :adapter)
  end

  def normalize({:degraded, reason, metadata}) when is_map(metadata) do
    degraded(reason, metadata, probe_kind: :adapter)
  end

  def normalize({:unavailable, reason}) do
    unavailable(reason, %{}, probe_kind: :adapter)
  end

  def normalize({:unavailable, reason, metadata}) when is_map(metadata) do
    unavailable(reason, metadata, probe_kind: :adapter)
  end

  def normalize({:error, reason}) do
    unavailable(:source_connection_failed, %{adapter_error: inspect(reason)},
      probe_kind: :adapter
    )
  end

  def normalize(other) do
    degraded(:source_probe_unexpected_result, %{result: inspect(other)}, probe_kind: :adapter)
  end

  @spec merge_metadata(t(), map()) :: t()
  def merge_metadata(%__MODULE__{} = probe, metadata) when is_map(metadata) do
    %{probe | metadata: Map.merge(probe.metadata, metadata)}
  end

  @spec new(health(), atom() | binary(), map(), keyword()) :: t()
  def new(source_health, reason, metadata \\ %{}, opts \\ [])
      when source_health in [:healthy, :degraded, :unavailable, :unknown] and is_map(metadata) do
    %__MODULE__{
      source_health: source_health,
      reason: reason,
      probe_kind: Keyword.get(opts, :probe_kind, :descriptor),
      message: Keyword.get(opts, :message),
      metadata: metadata
    }
  end
end
