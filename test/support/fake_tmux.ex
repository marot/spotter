defmodule Spotter.TestSupport.FakeTmux do
  @moduledoc false

  def start_link do
    Agent.start_link(fn -> [] end, name: __MODULE__)
  end

  def stop do
    if Process.whereis(__MODULE__), do: Agent.stop(__MODULE__)
  end

  def calls do
    Agent.get(__MODULE__, & &1)
  end

  def launch_project_review(project_id, token, port) do
    Agent.update(__MODULE__, &[{project_id, token, port} | &1])

    Application.get_env(
      :spotter,
      :fake_tmux_launch_result,
      {:ok, "spotter-review-project-test"}
    )
  end

  def kill_session(_name), do: :ok
end
