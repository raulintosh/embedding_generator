defmodule Mix.Tasks.EmbeddingGenerator.ProcessPending do
  use Mix.Task

  @shortdoc "Process pending images for embedding generation"

  @moduledoc """
  Processes pending images (with null embeddings) for embedding generation.

  ## Usage

      mix embedding_generator.process_pending [options]

  ## Options

      --batch-size, -b  The number of images to process in a batch
                        Defaults to the configured batch size (5)

  ## Examples

      # Process with default batch size
      mix embedding_generator.process_pending

      # Process with custom batch size
      mix embedding_generator.process_pending --batch-size 10
      mix embedding_generator.process_pending -b 10
  """

  def run(args) do
    # Parse arguments
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [batch_size: :integer],
        aliases: [b: :batch_size]
      )

    batch_size = Keyword.get(opts, :batch_size)

    # Start application
    {:ok, _} = Application.ensure_all_started(:embedding_generator)

    # Call batch processor
    case EmbeddingGenerator.BatchProcessor.schedule_pending_embeddings(batch_size) do
      {:ok, count} ->
        IO.puts("Scheduled #{count} images for embedding generation")

      error ->
        IO.puts("Error scheduling jobs: #{inspect(error)}")
    end
  end
end
