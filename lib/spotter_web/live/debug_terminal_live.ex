defmodule SpotterWeb.DebugTerminalLive do
  @moduledoc """
  Debug terminal that launches a plain shell via PTY, bypassing tmux.
  Useful for isolating xterm.js rendering issues from tmux control mode parsing.
  """
  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, cols: 80, rows: 24)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="header">
      <a href="/">&larr; Back</a>
      <span>Debug Terminal (raw PTY, no tmux) &mdash; {@cols}x{@rows}</span>
    </div>
    <div style="display: flex; justify-content: center; align-items: flex-start; padding: 2rem;">
      <div style="border-radius: 8px; overflow: hidden; box-shadow: 0 8px 32px rgba(0,0,0,0.5); border: 1px solid #333;">
        <div style="background: #2d2d3f; padding: 8px 12px; display: flex; align-items: center; gap: 8px;">
          <span style="width: 12px; height: 12px; border-radius: 50%; background: #ff5f56; display: inline-block;">
          </span>
          <span style="width: 12px; height: 12px; border-radius: 50%; background: #ffbd2e; display: inline-block;">
          </span>
          <span style="width: 12px; height: 12px; border-radius: 50%; background: #27c93f; display: inline-block;">
          </span>
          <span style="flex: 1; text-align: center; font-size: 0.8rem; color: #888;">
            debug (raw PTY)
          </span>
        </div>
        <div
          id="terminal"
          phx-hook="Terminal"
          data-pane-id="debug"
          data-cols={@cols}
          data-rows={@rows}
          phx-update="ignore"
          style="padding: 4px;"
        >
        </div>
      </div>
    </div>
    """
  end
end
