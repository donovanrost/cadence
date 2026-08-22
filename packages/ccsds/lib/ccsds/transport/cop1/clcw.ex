defmodule CCSDS.Transport.COP1.CLCW do
  @moduledoc """
  Communications Link Control Word (CLCW).
  """

  @type bit :: 0 | 1

  @type t :: %__MODULE__{
          control_word_type: bit(),
          version: 0..3,
          status: 0..7,
          cop_in_effect: 0..3,
          vcid: 0..63,
          spare_1: 0..3,
          no_rf_available: bit(),
          no_bit_lock: bit(),
          lockout: bit(),
          wait: bit(),
          retransmit: bit(),
          farm_b_counter: 0..3,
          spare_2: bit(),
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
            farm_b_counter: 0,
            spare_2: 0,
            report_value: 0

  @spec new(map() | keyword()) :: t()
  def new(attrs \\ %{}) when is_map(attrs) or is_list(attrs) do
    attrs = Map.new(attrs)
    struct(__MODULE__, attrs)
  end

  @spec encode(t()) :: {:ok, binary()} | {:error, term()}
  def encode(%__MODULE__{} = clcw) do
    with :ok <- validate(clcw) do
      {:ok,
       <<
         clcw.control_word_type::1,
         clcw.version::2,
         clcw.status::3,
         clcw.cop_in_effect::2,
         clcw.vcid::6,
         clcw.spare_1::2,
         clcw.no_rf_available::1,
         clcw.no_bit_lock::1,
         clcw.lockout::1,
         clcw.wait::1,
         clcw.retransmit::1,
         clcw.farm_b_counter::2,
         clcw.spare_2::1,
         clcw.report_value::8
       >>}
    end
  end

  @spec decode(binary()) :: {:ok, t()} | {:error, term()}
  def decode(<<
        control_word_type::1,
        version::2,
        status::3,
        cop_in_effect::2,
        vcid::6,
        spare_1::2,
        no_rf_available::1,
        no_bit_lock::1,
        lockout::1,
        wait::1,
        retransmit::1,
        farm_b_counter::2,
        spare_2::1,
        report_value::8
      >>) do
    {:ok,
     %__MODULE__{
       control_word_type: control_word_type,
       version: version,
       status: status,
       cop_in_effect: cop_in_effect,
       vcid: vcid,
       spare_1: spare_1,
       no_rf_available: no_rf_available,
       no_bit_lock: no_bit_lock,
       lockout: lockout,
       wait: wait,
       retransmit: retransmit,
       farm_b_counter: farm_b_counter,
       spare_2: spare_2,
       report_value: report_value
     }}
  end

  def decode(_), do: {:error, :invalid_length}

  defp validate(%__MODULE__{} = clcw) do
    checks = [
      fn -> validate_bit(clcw.control_word_type, :control_word_type) end,
      fn -> validate_range(clcw.version, 0, 3, :version) end,
      fn -> validate_range(clcw.status, 0, 7, :status) end,
      fn -> validate_range(clcw.cop_in_effect, 0, 3, :cop_in_effect) end,
      fn -> validate_range(clcw.vcid, 0, 63, :vcid) end,
      fn -> validate_range(clcw.spare_1, 0, 3, :spare_1) end,
      fn -> validate_bit(clcw.no_rf_available, :no_rf_available) end,
      fn -> validate_bit(clcw.no_bit_lock, :no_bit_lock) end,
      fn -> validate_bit(clcw.lockout, :lockout) end,
      fn -> validate_bit(clcw.wait, :wait) end,
      fn -> validate_bit(clcw.retransmit, :retransmit) end,
      fn -> validate_range(clcw.farm_b_counter, 0, 3, :farm_b_counter) end,
      fn -> validate_bit(clcw.spare_2, :spare_2) end,
      fn -> validate_range(clcw.report_value, 0, 255, :report_value) end
    ]

    Enum.reduce_while(checks, :ok, fn check, _acc ->
      case check.() do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_bit(value, _field) when value in [0, 1], do: :ok
  defp validate_bit(value, field), do: {:error, {:invalid_field, field, value}}

  defp validate_range(value, min, max, _field)
       when is_integer(value) and value >= min and value <= max,
       do: :ok

  defp validate_range(value, _min, _max, field),
    do: {:error, {:invalid_field, field, value}}
end
