defmodule SpotterWeb.PaneViewLive do
  use Phoenix.LiveView

  alias Spotter.Services.Tmux

  @impl true
  def mount(%{"pane_id" => pane_num}, _session, socket) do
    pane_id = Tmux.num_to_pane_id(pane_num)
    {:ok, assign(socket, pane_id: pane_id)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="header">
      <a href="/">&larr; Back</a>
      <span>Pane: {@pane_id}</span>
    </div>
    <div style="display: flex; flex-direction: column; height: calc(100vh - 40px); padding: 0.5rem;">
      <div style="flex: 1; border-radius: 8px; overflow: hidden; box-shadow: 0 8px 32px rgba(0,0,0,0.5); border: 1px solid #333; display: flex; flex-direction: column;">
        <div style="background: #2d2d3f; padding: 8px 12px; display: flex; align-items: center; gap: 8px;">
          <span style="width: 12px; height: 12px; border-radius: 50%; background: #ff5f56; display: inline-block;"></span>
          <span style="width: 12px; height: 12px; border-radius: 50%; background: #ffbd2e; display: inline-block;"></span>
          <span style="width: 12px; height: 12px; border-radius: 50%; background: #27c93f; display: inline-block;"></span>
          <span style="flex: 1; text-align: center; font-size: 0.8rem; color: #888;">{@pane_id}</span>
        </div>
        <div
          id="terminal"
          phx-hook="Terminal"
          data-pane-id={@pane_id}
          phx-update="ignore"
          style="flex: 1; padding: 4px;"
        >
        </div>
      </div>
    </div>
    """
  end
end
