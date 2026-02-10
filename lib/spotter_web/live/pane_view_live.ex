defmodule SpotterWeb.PaneViewLive do
  use Phoenix.LiveView

  @impl true
  def mount(%{"pane_id" => pane_num}, _session, socket) do
    pane_id = Spotter.Services.Tmux.num_to_pane_id(pane_num)
    {:ok, assign(socket, pane_id: pane_id)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="header">
      <a href="/">&larr; Back</a>
      <span>Pane: {@pane_id}</span>
    </div>
    <div id="terminal" class="terminal-container" phx-hook="Terminal" data-pane-id={@pane_id} phx-update="ignore">
    </div>
    """
  end
end
