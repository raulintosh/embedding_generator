defmodule EmbeddingGenerator.S3Service do
  @moduledoc """
  Service for interacting with Digital Ocean Spaces (S3-compatible storage).

  This module provides functions to download images from Digital Ocean Spaces
  using the ExAws library.
  """

  require Logger

  @doc """
  Downloads a file from Digital Ocean Spaces using the provided S3 URL.

  ## Parameters

  - `s3_url`: The full URL to the file in Digital Ocean Spaces

  ## Returns

  - Binary data of the downloaded file

  ## Examples

      iex> binary = EmbeddingGenerator.S3Service.download_file("https://bucket-name.nyc3.digitaloceanspaces.com/path/to/image.jpg")
      iex> is_binary(binary)
      true
  """
  def download_file(s3_url) do
    start_time = System.monotonic_time(:millisecond)

    # Parse the S3 URL to extract the path
    path = extract_path_from_url(s3_url)
    bucket = System.get_env("BUCKET_NAME")

    Logger.info("Starting download of file from S3: #{path}")
    Logger.debug("Bucket: #{bucket}, Path: #{path}, Full URL: #{s3_url}")

    # Download the file from S3
    download_start_time = System.monotonic_time(:millisecond)

    result =
      try do
        response =
          ExAws.S3.get_object(bucket, path)
          |> ExAws.request()

        download_duration = System.monotonic_time(:millisecond) - download_start_time

        case response do
          {:ok, %{body: image_binary, status_code: 200}} ->
            size = byte_size(image_binary)
            total_duration = System.monotonic_time(:millisecond) - start_time

            Logger.info("Successfully downloaded file (#{size} bytes) in #{total_duration}ms")
            Logger.debug("Content type: #{get_content_type(path)}")

            if size == 0 do
              Logger.warn("Downloaded file is empty (0 bytes)")
            end

            {:ok, image_binary}

          {:ok, %{status_code: status_code}} ->
            Logger.error("Failed to download file: Unexpected status code #{status_code}")
            {:error, :unexpected_status_code}

          {:error, reason} ->
            Logger.error("Failed to download file: #{inspect(reason)}")
            {:error, reason}
        end
      rescue
        e ->
          Logger.error("Error downloading file: #{Exception.message(e)}")
          Logger.debug("Exception: #{inspect(e)}")
          {:error, e}
      end

    case result do
      {:ok, binary} ->
        binary

      {:error, _} ->
        Logger.error("Returning empty binary due to download error")
        <<>>
    end
  end

  @doc """
  Extracts the path from an S3 URL.

  ## Parameters

  - `s3_url`: The full URL to the file in Digital Ocean Spaces

  ## Returns

  - String representing the path within the bucket

  ## Examples

      iex> EmbeddingGenerator.S3Service.extract_path_from_url("https://bucket-name.nyc3.digitaloceanspaces.com/path/to/image.jpg")
      "path/to/image.jpg"
  """
  def extract_path_from_url(s3_url) do
    # Extract the path from the S3 URL
    # Example: https://bucket-name.nyc3.digitaloceanspaces.com/path/to/image.jpg
    # Returns: path/to/image.jpg
    uri = URI.parse(s3_url)
    path = String.replace_prefix(uri.path, "/", "")
    Logger.debug("Extracted path '#{path}' from URL: #{s3_url}")
    path
  end

  @doc """
  Determines the content type based on the file extension.

  ## Parameters

  - `path`: The path to the file

  ## Returns

  - String representing the MIME type
  """
  defp get_content_type(path) do
    extension =
      path
      |> String.split(".")
      |> List.last()
      |> String.downcase()

    case extension do
      "jpg" -> "image/jpeg"
      "jpeg" -> "image/jpeg"
      "png" -> "image/png"
      "gif" -> "image/gif"
      "webp" -> "image/webp"
      "svg" -> "image/svg+xml"
      "tiff" -> "image/tiff"
      "bmp" -> "image/bmp"
      _ -> "application/octet-stream"
    end
  end
end
