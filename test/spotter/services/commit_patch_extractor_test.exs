defmodule Spotter.Services.CommitPatchExtractorTest do
  use ExUnit.Case, async: true

  alias Spotter.Services.CommitPatchExtractor

  describe "parse_patch/1" do
    test "parses single file with one hunk" do
      patch = """
      diff --git a/lib/foo.ex b/lib/foo.ex
      index abc1234..def5678 100644
      --- a/lib/foo.ex
      +++ b/lib/foo.ex
      @@ -10,0 +11,3 @@ defmodule Foo do
      +  def bar do
      +    :ok
      +  end
      """

      result = CommitPatchExtractor.parse_patch(patch)

      assert length(result) == 1
      file = hd(result)
      assert file.path == "lib/foo.ex"
      assert length(file.hunks) == 1

      hunk = hd(file.hunks)
      assert hunk.new_start == 11
      assert hunk.new_len == 3
      assert hunk.lines == ["  def bar do", "    :ok", "  end"]
    end

    test "parses multiple files" do
      patch = """
      diff --git a/lib/a.ex b/lib/a.ex
      index 1111111..2222222 100644
      --- a/lib/a.ex
      +++ b/lib/a.ex
      @@ -1,0 +2,1 @@
      +new_line
      diff --git a/lib/b.ex b/lib/b.ex
      index 3333333..4444444 100644
      --- a/lib/b.ex
      +++ b/lib/b.ex
      @@ -5,0 +6,2 @@
      +line_one
      +line_two
      """

      result = CommitPatchExtractor.parse_patch(patch)

      assert length(result) == 2
      assert Enum.at(result, 0).path == "lib/a.ex"
      assert Enum.at(result, 1).path == "lib/b.ex"
      assert length(Enum.at(result, 1).hunks) == 1
      assert hd(Enum.at(result, 1).hunks).new_len == 2
    end

    test "skips deletion-only hunks" do
      patch = """
      diff --git a/lib/foo.ex b/lib/foo.ex
      index abc1234..def5678 100644
      --- a/lib/foo.ex
      +++ b/lib/foo.ex
      @@ -10,3 +10,0 @@
      -removed line 1
      -removed line 2
      -removed line 3
      """

      result = CommitPatchExtractor.parse_patch(patch)

      # File should be excluded since all hunks are deletion-only
      assert result == []
    end

    test "handles empty output" do
      assert CommitPatchExtractor.parse_patch("") == []
    end
  end
end
