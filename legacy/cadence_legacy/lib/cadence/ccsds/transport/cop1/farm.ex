defmodule Cadence.CCSDS.Transport.COP1.FARM do
  @moduledoc """
  Spacecraft-side COP-1 FARM state (skeleton).

  This module holds FARM state and emits a CLCW snapshot. It intentionally
  omits TC framing and full COP-1 sequencing for now.
  """

  alias Cadence.CCSDS.Transport.COP1.CLCW

  @type t :: %__MODULE__{
          control_word_type: 0..3,
          version: 0..3,
          status: 0..7,
          cop_in_effect: CLCW.bit(),
          vcid: 0..63,
          spare_1: 0..3,
          no_rf_available: CLCW.bit(),
          no_bit_lock: CLCW.bit(),
          lockout: CLCW.bit(),
          wait: CLCW.bit(),
          retransmit: CLCW.bit(),
          farm_busy: CLCW.bit(),
          spare_2: 0..3,
          report_value: 0..255
        }

  defstruct control_word_type: 0,
            version: 0,
            status: 0,
            cop_in_effect: 1,
            vcid: 0,
            spare_1: 0,
            no_rf_available: 0,
            no_bit_lock: 0,
            lockout: 0,
            wait: 0,
            retransmit: 0,
            farm_busy: 0,
            spare_2: 0,
            report_value: 0

  @spec init(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def init(opts \\ %{}) when is_map(opts) or is_list(opts) do
    farm = struct(__MODULE__, Map.new(opts))

    case validate(farm) do
      :ok -> {:ok, farm}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec update(t(), map() | keyword()) :: {:ok, t()} | {:error, term()}
  def update(%__MODULE__{} = farm, attrs) when is_map(attrs) or is_list(attrs) do
    updated = struct(farm, Map.new(attrs))

    case validate(updated) do
      :ok -> {:ok, updated}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec clcw(t()) :: CLCW.t()
  def clcw(%__MODULE__{} = farm) do
    CLCW.new(%{
      control_word_type: farm.control_word_type,
      version: farm.version,
      status: farm.status,
      cop_in_effect: farm.cop_in_effect,
      vcid: farm.vcid,
      spare_1: farm.spare_1,
      no_rf_available: farm.no_rf_available,
      no_bit_lock: farm.no_bit_lock,
      lockout: farm.lockout,
      wait: farm.wait,
      retransmit: farm.retransmit,
      farm_busy: farm.farm_busy,
      spare_2: farm.spare_2,
      report_value: farm.report_value
    })
  end

  @spec encode_clcw(t()) :: {:ok, binary()} | {:error, term()}
  def encode_clcw(%__MODULE__{} = farm) do
    farm
    |> clcw()
    |> CLCW.encode()
  end

  @spec ingest(t(), map() | non_neg_integer()) :: {:ok, t()} | {:error, term()}
  def ingest(%__MODULE__{} = farm, %{frame_seq: seq, vcid: vcid}) when is_integer(seq) do
    report_value = rem(seq, 256)
    {:ok, %{farm | report_value: report_value, vcid: vcid}}
  end

  def ingest(%__MODULE__{} = farm, %{frame_seq: seq}) when is_integer(seq) do
    report_value = rem(seq, 256)
    {:ok, %{farm | report_value: report_value}}
  end

  def ingest(%__MODULE__{} = farm, seq) when is_integer(seq) do
    report_value = rem(seq, 256)
    {:ok, %{farm | report_value: report_value}}
  end

  defp validate(%__MODULE__{} = farm) do
    case encode_clcw(farm) do
      {:ok, _binary} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
