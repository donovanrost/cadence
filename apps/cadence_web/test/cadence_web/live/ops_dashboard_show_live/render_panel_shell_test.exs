defmodule CadenceWeb.OpsDashboardShowLive.RenderPanelShellTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.RenderPanelModel

  test "open? reflects shell panel visibility" do
    assert RenderPanelModel.open?(%{panel: :add_widget}) == true
    assert RenderPanelModel.open?(%{panel: nil}) == false
  end
end
