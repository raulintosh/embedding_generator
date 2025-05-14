defmodule EmbeddingGenerator.Workers.BatchEmbeddingWorker do
  use Oban.Worker, queue: :embeddings

  alias EmbeddingGenerator.{Repo, S3Service, OllamaService, BatchProcessor}
  alias EmbeddingGenerator.Schema.Image

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"image_ids" => image_ids}}) do
    Logger.info("Processing batch of #{length(image_ids)} images")

    # Process each image in the batch
    results =
      Enum.map(image_ids, fn image_id ->
        case process_image(image_id) do
          :ok ->
            Logger.info("Successfully processed image #{image_id}")
            {:ok, image_id}

          {:error, reason} ->
            Logger.error("Failed to process image #{image_id}: #{inspect(reason)}")
            {:error, image_id, reason}
        end
      end)

    # Count successes and failures
    successes =
      Enum.count(results, fn
        {:ok, _} -> true
        _ -> false
      end)

    failures =
      Enum.count(results, fn
        {:error, _, _} -> true
        _ -> false
      end)

    Logger.info("Batch processing completed: #{successes} succeeded, #{failures} failed")

    # Schedule next batch if there are more images to process
    BatchProcessor.schedule_pending_embeddings()

    :ok
  end

  defp process_image(image_id) do
    # Get image from database
    case Repo.get(Image, image_id) do
      nil ->
        {:error, :image_not_found}

      image ->
        try do
          # Download image from S3
          image_binary = S3Service.download_file(image.s3_url)

          # Convert to base64
          image_base64 = Base.encode64(image_binary)

          # Generate embedding using Ollama
          embedding = OllamaService.generate_embedding(image_base64)

          # Update image record with embedding
          image
          |> Ecto.Changeset.change(%{embedding: embedding})
          |> Repo.update()
          |> case do
            {:ok, _updated} -> :ok
            error -> error
          end
        rescue
          e ->
            Logger.error("Exception while processing image #{image_id}: #{inspect(e)}")
            {:error, Exception.message(e)}
        end
    end
  end
end
