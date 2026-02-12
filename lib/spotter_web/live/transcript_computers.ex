defmodule SpotterWeb.Live.TranscriptComputers do
  @moduledoc """
  Shared AshComputer definitions for transcript rendering state.

  Attached by both `SessionLive` and `SubagentLive` to provide a single
  reactive pipeline from raw messages to visible transcript lines.
  """
  use AshComputer

  alias Spotter.Services.TranscriptRenderer

  computer :transcript_view do
    input :messages do
      initial []
    end

    input :session_cwd do
      initial nil
    end

    input :show_debug do
      initial false
    end

    input :expanded_tool_groups do
      initial MapSet.new()
    end

    val :rendered_lines do
      compute(fn %{messages: messages, session_cwd: session_cwd} ->
        opts = if session_cwd, do: [session_cwd: session_cwd], else: []
        TranscriptRenderer.render(messages, opts)
      end)

      depends_on([:messages, :session_cwd])
    end

    val :visible_lines do
      compute(fn %{rendered_lines: rendered_lines, expanded_tool_groups: expanded} ->
        Enum.reject(rendered_lines, fn line ->
          line[:hidden_by_default] == true and
            not MapSet.member?(expanded, line[:tool_result_group])
        end)
      end)

      depends_on([:rendered_lines, :expanded_tool_groups])
    end

    event :toggle_tool_result_group do
      handle(fn %{expanded_tool_groups: expanded}, %{"group" => group} ->
        new_expanded =
          if MapSet.member?(expanded, group) do
            MapSet.delete(expanded, group)
          else
            MapSet.put(expanded, group)
          end

        %{expanded_tool_groups: new_expanded}
      end)
    end
  end
end
