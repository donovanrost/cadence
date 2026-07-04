defmodule CadenceWeb.Layouts do
  @moduledoc false

  use CadenceWeb, :html

  import CadenceWeb.Components.OpsShell
  import CadenceWeb.Components.Sidebar

  embed_templates "layouts/*"
end
