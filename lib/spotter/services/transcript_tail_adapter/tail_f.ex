defmodule Spotter.Services.TranscriptTailAdapter.TailF do
  @moduledoc false

  @behaviour Spotter.Services.TranscriptTailAdapter

  @impl true
  def start(_session_id, transcript_path, caller_pid, _opts \\ []) do
    script = Application.app_dir(:spotter, "priv/scripts/tail_wrapper.sh")

    if File.exists?(transcript_path) do
      port =
        Port.open({:spawn_executable, script}, [
          :binary,
          :exit_status,
          :use_stdio,
          :stderr_to_stdout,
          args: [transcript_path]
        ])

      {:ok, %{port: port, caller: caller_pid, path: transcript_path}}
    else
      {:error, :file_not_found}
    end
  end

  @impl true
  def stop(%{port: port}) do
    if Port.info(port) do
      Port.close(port)
    end

    :ok
  rescue
    _ -> :ok
  end
end
