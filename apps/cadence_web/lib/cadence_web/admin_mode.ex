defmodule CadenceWeb.AdminMode do
  @moduledoc false

  @spec active?(term()) :: boolean()
  def active?(expires_at) when is_integer(expires_at) do
    expires_at > System.system_time(:second)
  end

  def active?(_expires_at), do: false

  @spec expires_at() :: integer()
  def expires_at do
    System.system_time(:second) + ttl_seconds()
  end

  defp ttl_seconds do
    Application.get_env(:cadence_web, :admin_mode_ttl_seconds, 3_600)
  end
end
