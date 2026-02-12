defmodule Spotter.Services.TranscriptTailAdapter do
  @moduledoc false

  @type adapter_state :: term()

  @callback start(
              session_id :: String.t(),
              transcript_path :: String.t(),
              caller_pid :: pid(),
              opts :: keyword()
            ) :: {:ok, adapter_state()} | {:error, term()}

  @callback stop(adapter_state()) :: :ok
end
