defmodule CadenceSimulator.COP1.CLCWInjector do
  @moduledoc """
  Applies deterministic overrides to CLCW fields for simulator error injection.
  """

  alias Cadence.CCSDS.Transport.COP1.CLCW

  @type schedule_entry :: %{
          at: non_neg_integer(),
          overrides: map()
        }

  @type t :: %__MODULE__{
          overrides: map(),
          schedule: [schedule_entry()]
        }

  defstruct overrides: %{}, schedule: []

  @bit_fields [
    :no_rf_available,
    :no_bit_lock,
    :lockout,
    :wait,
    :retransmit
  ]

  @allowed_fields [
    :control_word_type,
    :version,
    :status,
    :cop_in_effect,
    :vcid,
    :spare_1,
    :no_rf_available,
    :no_bit_lock,
    :lockout,
    :wait,
    :retransmit,
    :farm_b_counter,
    :spare_2,
    :report_value
  ]

  @string_keys Map.new(@allowed_fields, fn key -> {Atom.to_string(key), key} end)

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      overrides: opts |> Keyword.get(:overrides, %{}) |> normalize_overrides(),
      schedule: opts |> Keyword.get(:schedule, []) |> normalize_schedule()
    }
  end

  @spec apply(t(), CLCW.t(), non_neg_integer() | nil) :: CLCW.t()
  def apply(%__MODULE__{} = injector, %CLCW{} = clcw, step \\ 0) do
    struct(clcw, resolve_overrides(injector, step))
  end

  @spec resolve_overrides(t(), non_neg_integer() | nil) :: map()
  def resolve_overrides(%__MODULE__{} = injector, step) do
    step = normalize_step(step)
    schedule_overrides = schedule_overrides(injector.schedule, step)
    Map.merge(injector.overrides, schedule_overrides)
  end

  defp schedule_overrides(schedule, step) do
    schedule
    |> Enum.filter(fn %{at: at} -> step >= at end)
    |> Enum.reduce(%{}, fn %{overrides: overrides}, acc -> Map.merge(acc, overrides) end)
  end

  defp normalize_schedule(schedule) when is_list(schedule) do
    schedule
    |> Enum.map(&normalize_schedule_entry/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.at)
  end

  defp normalize_schedule(_), do: []

  defp normalize_schedule_entry(entry) when is_map(entry) do
    at =
      entry
      |> fetch_value([:at, "at", :step, "step"])
      |> parse_integer()

    overrides =
      entry
      |> fetch_value([:overrides, "overrides", :flags, "flags"])
      |> normalize_overrides()

    if is_integer(at) and at >= 0 and overrides != %{} do
      %{at: at, overrides: overrides}
    else
      nil
    end
  end

  defp normalize_schedule_entry(_), do: nil

  defp normalize_overrides(nil), do: %{}

  defp normalize_overrides(overrides) when is_map(overrides) do
    Enum.reduce(overrides, %{}, fn {key, value}, acc ->
      case normalize_key(key) do
        nil -> acc
        atom_key -> Map.put(acc, atom_key, normalize_value(atom_key, value))
      end
    end)
  end

  defp normalize_overrides(_), do: %{}

  defp normalize_key(key) when is_atom(key), do: if(key in @allowed_fields, do: key, else: nil)
  defp normalize_key(key) when is_binary(key), do: Map.get(@string_keys, key)
  defp normalize_key(_), do: nil

  defp normalize_value(key, value) when key in @bit_fields do
    case value do
      true -> 1
      false -> 0
      other -> parse_integer(other) || other
    end
  end

  defp normalize_value(_key, value), do: parse_integer(value) || value

  defp normalize_step(nil), do: 0
  defp normalize_step(step) when is_integer(step) and step >= 0, do: step
  defp normalize_step(step), do: parse_integer(step) || 0

  defp fetch_value(map, keys), do: Enum.find_value(keys, fn key -> Map.get(map, key) end)
  defp parse_integer(nil), do: nil
  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_integer(_), do: nil
end
