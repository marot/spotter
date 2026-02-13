defmodule Spotter.Services.ExplainAnnotations do
  @moduledoc false

  alias Spotter.Transcripts.Jobs.ExplainAnnotation

  def topic(annotation_id), do: "annotation_explain:#{annotation_id}"

  def enqueue(annotation_id) do
    %{"annotation_id" => annotation_id}
    |> ExplainAnnotation.new()
    |> Oban.insert()
  end
end
