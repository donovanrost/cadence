defmodule CadenceWeb.Layouts do
  @moduledoc false

  use CadenceWeb, :html

  import CadenceWeb.Components.OpsShell
  import CadenceWeb.Components.OpsApplicationDock
  import CadenceWeb.Components.Sidebar

  embed_templates "layouts/*"

  defp provider_accounts_visible?(%{capabilities: capabilities}) do
    MapSet.member?(capabilities, :organization_admin) or
      MapSet.member?(capabilities, :platform_admin)
  end

  defp provider_accounts_visible?(_scope), do: false
end
