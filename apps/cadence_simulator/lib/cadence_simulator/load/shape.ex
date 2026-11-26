defmodule CadenceSimulator.Load.Shape do
  @moduledoc false

  def fleet(craft, sites) do
    Enum.map(1..craft, fn scid -> {scid, rem(scid - 1, sites)} end)
  end

  def in_contact?(_scid, _sites, "peak", _per_site), do: true

  def in_contact?(scid, sites, "average", per_site),
    do: div(scid - 1, sites) < per_site

  def validate(craft, shape, per_site) do
    cond do
      craft not in 1..1023 -> {:error, "--craft must be between 1 and 1023 (TM SCIDs)"}
      shape not in ["average", "peak"] -> {:error, "--shape must be average or peak"}
      per_site not in [8, 16] -> {:error, "--per-site must be 8 or 16"}
      true -> :ok
    end
  end
end
