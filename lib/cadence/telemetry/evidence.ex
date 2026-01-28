defmodule Cadence.Telemetry.Evidence do
  @moduledoc """
  Typed, attributable evidence attached to a packet envelope.
  """

  @type t :: %__MODULE__{
          kind: atom(),
          value: term(),
          source: atom() | tuple(),
          confidence: :high | :medium | :low,
          at: DateTime.t() | nil,
          notes: binary() | nil
        }

  defstruct [:kind, :value, :source, :confidence, :at, :notes]

  @spec new(atom(), term(), keyword()) :: t()
  def new(kind, value, opts \\ []) when is_atom(kind) do
    %__MODULE__{
      kind: kind,
      value: value,
      source: Keyword.get(opts, :source, :unspecified),
      confidence: Keyword.get(opts, :confidence, :medium),
      at: Keyword.get(opts, :at),
      notes: Keyword.get(opts, :notes)
    }
  end

  @spec scid(term(), atom() | tuple(), :high | :medium | :low) :: t()
  def scid(value, source, confidence \\ :high) do
    new(:scid, value, source: source, confidence: confidence)
  end

  @spec vcid(term(), atom() | tuple(), :high | :medium | :low) :: t()
  def vcid(value, source, confidence \\ :high) do
    new(:vcid, value, source: source, confidence: confidence)
  end

  @spec map_id(term(), atom() | tuple(), :high | :medium | :low) :: t()
  def map_id(value, source, confidence \\ :high) do
    new(:map_id, value, source: source, confidence: confidence)
  end

  @spec apid(term(), atom() | tuple(), :high | :medium | :low) :: t()
  def apid(value, source, confidence \\ :high) do
    new(:apid, value, source: source, confidence: confidence)
  end

  @spec interface_id(term(), atom() | tuple(), :high | :medium | :low) :: t()
  def interface_id(value, source, confidence \\ :high) do
    new(:interface_id, value, source: source, confidence: confidence)
  end

  @spec target_hint(term(), atom() | tuple(), :high | :medium | :low) :: t()
  def target_hint(value, source, confidence \\ :low) do
    new(:target_hint, value, source: source, confidence: confidence)
  end

  @spec packet_format(term(), atom() | tuple(), :high | :medium | :low) :: t()
  def packet_format(value, source, confidence \\ :medium) do
    new(:packet_format, value, source: source, confidence: confidence)
  end
end
