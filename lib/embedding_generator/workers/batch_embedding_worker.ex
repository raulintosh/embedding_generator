defmodule EmbeddingGenerator.Workers.BatchEmbeddingWorker do
  @moduledoc """
  Oban worker for processing batches of images to generate embeddings.

  This worker:
  1. Takes a batch of image IDs
  2. Downloads each image from Digital Ocean Spaces
  3. Generates embeddings using Ollama
  4. Updates the database with the embeddings
  5. Schedules the next batch if more images need processing
  """

  use Oban.Worker, queue: :embeddings, max_attempts: 3

  alias EmbeddingGenerator.{Repo, S3Service, OllamaService, BatchProcessor}
  alias EmbeddingGenerator.Schema.Image

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"image_ids" => image_ids}, attempt: attempt}) do
    batch_size = length(image_ids)
    start_time = System.monotonic_time(:millisecond)

    Logger.info("Starting batch processing of #{batch_size} images (attempt #{attempt})")
    Logger.debug("Image IDs in batch: #{inspect(image_ids)}")

    # Process each image in the batch
    results =
      Enum.map(image_ids, fn image_id ->
        image_start_time = System.monotonic_time(:millisecond)
        Logger.debug("Starting processing of image #{image_id}")

        result = process_image(image_id)

        image_duration = System.monotonic_time(:millisecond) - image_start_time

        case result do
          :ok ->
            Logger.info("Successfully processed image #{image_id} in #{image_duration}ms")
            {:ok, image_id, image_duration}

          {:error, reason} ->
            Logger.error(
              "Failed to process image #{image_id} after #{image_duration}ms: #{inspect(reason)}"
            )

            {:error, image_id, reason, image_duration}
        end
      end)

    # Count successes and failures
    successes =
      Enum.count(results, fn
        {:ok, _, _} -> true
        _ -> false
      end)

    failures =
      Enum.count(results, fn
        {:error, _, _, _} -> true
        _ -> false
      end)

    # Calculate statistics
    total_duration = System.monotonic_time(:millisecond) - start_time

    avg_duration =
      case successes do
        0 ->
          0

        _ ->
          successful_durations =
            Enum.reduce(results, 0, fn
              {:ok, _, duration}, acc -> acc + duration
              _, acc -> acc
            end)

          div(successful_durations, successes)
      end

    # Log detailed results
    Logger.info(
      "Batch processing completed: #{successes}/#{batch_size} succeeded, #{failures} failed"
    )

    Logger.info(
      "Total batch processing time: #{total_duration}ms, average per image: #{avg_duration}ms"
    )

    # Log failed image IDs for troubleshooting
    if failures > 0 do
      failed_ids =
        results
        |> Enum.filter(fn
          {:error, _, _, _} -> true
          _ -> false
        end)
        |> Enum.map(fn {:error, id, _, _} -> id end)

      Logger.warning("Failed image IDs: #{inspect(failed_ids)}")
    end

    # Schedule next batch if there are more images to process
    case BatchProcessor.schedule_pending_embeddings() do
      {:ok, next_batch_size} when next_batch_size > 0 ->
        Logger.info("Scheduled next batch with #{next_batch_size} images")

      {:ok, 0} ->
        Logger.info("No more images to process")

      {:error, reason} ->
        Logger.error("Failed to schedule next batch: #{inspect(reason)}")
    end

    :ok
  end

  # Processes a single image by downloading it, generating an embedding, and updating the database.
  defp process_image(image_id) do
    Logger.debug("Fetching image #{image_id} from database")

    # Get image from database
    case Repo.get(Image, image_id) do
      nil ->
        Logger.error("Image not found in database: #{image_id}")
        {:error, :image_not_found}

      image ->
        Logger.debug("Processing image: #{inspect(Map.take(image, [:id, :s3_url]))}")

        try do
          # Download image from S3
          Logger.debug("Downloading image from S3: #{image.s3_url}")
          download_start = System.monotonic_time(:millisecond)
          image_binary = S3Service.download_file(image.s3_url)
          download_duration = System.monotonic_time(:millisecond) - download_start

          binary_size = byte_size(image_binary)
          Logger.debug("Downloaded image (#{binary_size} bytes) in #{download_duration}ms")

          if binary_size == 0 do
            Logger.error("Downloaded image is empty (0 bytes)")
            {:error, :empty_image}
          end

          # Convert to base64
          Logger.debug("Converting image to base64")
          encode_start = System.monotonic_time(:millisecond)
          image_base64 = Base.encode64(image_binary)
          encode_duration = System.monotonic_time(:millisecond) - encode_start

          base64_size = byte_size(image_base64)
          Logger.debug("Converted image to base64 (#{base64_size} bytes) in #{encode_duration}ms")

          # Generate embedding using Ollama
          Logger.debug("Generating embedding using Ollama")
          embedding_start = System.monotonic_time(:millisecond)
          embedding = OllamaService.generate_embedding(image_base64)
          embedding_duration = System.monotonic_time(:millisecond) - embedding_start

          embedding_size = length(embedding)

          Logger.debug(
            "Generated embedding (#{embedding_size} dimensions) in #{embedding_duration}ms"
          )

          if embedding_size == 0 do
            Logger.error("Generated embedding is empty (0 dimensions)")
            {:error, :empty_embedding}
          end

          # Update image record with embedding
          Logger.debug("Updating image record with embedding")
          update_start = System.monotonic_time(:millisecond)

          result =
            image
            |> Ecto.Changeset.change(%{embedding: embedding})
            |> Repo.update()

          update_duration = System.monotonic_time(:millisecond) - update_start

          case result do
            {:ok, _updated} ->
              Logger.debug("Updated image record in #{update_duration}ms")
              :ok

            {:error, changeset} ->
              errors = changeset.errors
              Logger.error("Failed to update image record: #{inspect(errors)}")
              {:error, {:update_failed, errors}}
          end
        rescue
          e ->
            Logger.error("Exception while processing image #{image_id}: #{Exception.message(e)}")
            Logger.debug("Exception details: #{inspect(e)}")
            Logger.debug("Stacktrace: #{inspect(__STACKTRACE__)}")
            {:error, {:exception, Exception.message(e)}}
        end
    end
  end
end
