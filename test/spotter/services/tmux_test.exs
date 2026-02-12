defmodule Spotter.Services.TmuxTest do
  use ExUnit.Case, async: true

  alias Spotter.Services.Tmux

  describe "parse_list_panes_output/1" do
    test "parses valid pane line" do
      output = "%0\tmain\t0\t0\tbash\t200\t50\tbash\n"

      assert [pane] = Tmux.parse_list_panes_output(output)
      assert pane.pane_id == "%0"
      assert pane.session_name == "main"
      assert pane.window_index == 0
      assert pane.pane_index == 0
      assert pane.pane_title == "bash"
      assert pane.pane_width == 200
      assert pane.pane_height == 50
      assert pane.pane_current_command == "bash"
    end

    test "non-integer tokens default to 0" do
      output = "%1\tsess\tabc\t--\ttitle\tnope\t\tcmd\n"

      assert [pane] = Tmux.parse_list_panes_output(output)
      assert pane.window_index == 0
      assert pane.pane_index == 0
      assert pane.pane_width == 0
      assert pane.pane_height == 0
    end

    test "empty numeric tokens default to 0" do
      output = "%2\tsess\t\t\ttitle\t\t\tcmd\n"

      assert [pane] = Tmux.parse_list_panes_output(output)
      assert pane.window_index == 0
      assert pane.pane_index == 0
      assert pane.pane_width == 0
      assert pane.pane_height == 0
    end

    test "partial row with missing trailing fields" do
      output = "%3\tsess\t1\n"

      assert [pane] = Tmux.parse_list_panes_output(output)
      assert pane.pane_id == "%3"
      assert pane.session_name == "sess"
      assert pane.window_index == 1
      assert pane.pane_index == 0
      assert pane.pane_width == 0
      assert pane.pane_height == 0
      assert pane.pane_current_command == ""
    end

    test "mixed valid and malformed rows" do
      output =
        "%10\tgood\t1\t2\ttitle\t120\t40\tvim\n" <>
          "%11\tbad\tabc\t--\ttitle\t\t\tcmd\n"

      assert [good, bad] = Tmux.parse_list_panes_output(output)

      assert good.window_index == 1
      assert good.pane_width == 120
      assert good.pane_height == 40

      assert bad.window_index == 0
      assert bad.pane_index == 0
      assert bad.pane_width == 0
      assert bad.pane_height == 0
    end

    test "deduplicates by pane_id" do
      output =
        "%5\tsess\t0\t0\ttitle\t80\t24\tbash\n" <>
          "%5\tsess\t0\t0\ttitle\t80\t24\tbash\n"

      assert [_single] = Tmux.parse_list_panes_output(output)
    end

    test "empty output returns empty list" do
      assert [] = Tmux.parse_list_panes_output("")
    end
  end
end
