defmodule EmbeddingGenerator.OllamaService do
  @moduledoc """
  Service for interacting with the Ollama API to generate embeddings for images.

  This module provides functions to communicate with a local Ollama instance
  and generate vector embeddings for images using the llama3.2-vision model.
  """

  require Logger

  @base_url "http://127.0.0.1:11434"
  @model "llama3.2-vision:latest"
  @api_endpoint "/api/embed"

  @doc """
  Generates an embedding vector for an image using the Ollama API.

  ## Parameters

  - `image_base64`: Base64-encoded string of the image

  ## Returns

  - List of floats representing the embedding vector

  ## Examples

      iex> image_binary = File.read!("path/to/image.jpg")
      iex> image_base64 = Base.encode64(image_binary)
      iex> embedding = EmbeddingGenerator.OllamaService.generate_embedding(image_base64)
      iex> is_list(embedding)
      true
  """
  def generate_embedding(image_base64) do
    image_size = byte_size(image_base64)
    Logger.info("Starting embedding generation using Ollama model: #{@model}")
    Logger.debug("Image size (base64): #{image_size} bytes")

    start_time = System.monotonic_time(:millisecond)

    # Prepare the request payload
    payload = %{
      model: @model,
      prompt: image_base64
    }

    Logger.debug("Sending request to Ollama API at #{@base_url}#{@api_endpoint}")

    # Make the API call to Ollama
    request_start_time = System.monotonic_time(:millisecond)

    result =
      try do
        {:ok, response} =
          Finch.build(
            :post,
            "#{@base_url}#{@api_endpoint}",
            [{"Content-Type", "application/json"}],
            Jason.encode!(payload)
          )
          |> Finch.request(EmbeddingGenerator.Finch)

        request_duration = System.monotonic_time(:millisecond) - request_start_time
        Logger.debug("Ollama API request completed in #{request_duration}ms")

        # Parse the response
        parse_start_time = System.monotonic_time(:millisecond)
        {:ok, body} = Jason.decode(response.body)
        parse_duration = System.monotonic_time(:millisecond) - parse_start_time
        Logger.debug("Response parsing completed in #{parse_duration}ms")

        # Extract the embedding vector
        embedding = body["embedding"]

        if is_nil(embedding) do
          Logger.error("Failed to generate embedding: No embedding in response")
          Logger.debug("Response body: #{inspect(body)}")
          {:error, :no_embedding_in_response}
        else
          dimensions = length(embedding)
          total_duration = System.monotonic_time(:millisecond) - start_time

          Logger.info(
            "Successfully generated embedding with #{dimensions} dimensions in #{total_duration}ms"
          )

          Logger.debug("First 5 dimensions: #{inspect(Enum.take(embedding, 5))}")

          {:ok, embedding}
        end
      rescue
        e ->
          Logger.error("Error generating embedding: #{Exception.message(e)}")
          Logger.debug("Exception: #{inspect(e)}")
          {:error, e}
      end

    case result do
      {:ok, embedding} ->
        embedding

      {:error, error} ->
        Logger.error("Returning empty embedding due to error: #{inspect(error)}")
        []
    end
  end
end
