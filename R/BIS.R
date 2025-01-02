if (getRversion() >= "2.15.1") utils::globalVariables(c("obs_value"))

# Standardise column names
.clean_names <- function(x) {
  x <- make.unique(
    tolower(trimws(gsub("[[:space:]]", "_", sub(":.*$", "", x))))
  )

  return(x)
}

# Download a file from a given URL
.download_file <- function(file_url, ...) {
  # Save user options
  old_options <- options()

  # Restore user options on function exit
  on.exit(options(old_options))

  # Force minimum timeout of 300 for file download
  options(timeout = max(300, getOption("timeout")))

  file_path <- tryCatch({
    # Prepare temp file
    file_ext <- tools::file_ext(file_url)
    file_ext <- ifelse(file_ext == "", "", paste0(".", file_ext))
    tmp_file <- tempfile(fileext = file_ext)

    # Download data and store in temp file
    utils::download.file(file_url, tmp_file, mode = "wb")

    # Return path to temp tile
    file_path <- tmp_file

    file_path
  },
  error = function(x) {
    message(paste("Unable to download file:", file_url))
    message("The resource is unavailable or has changed.")
    message("To download large files, try increasing the download timeout:")
    message("options(timeout = 600)")
    message("Original error message:")
    message(x)
    return(NA)
  },
  warning = function(x) {
    message(paste("Unable to download file:", file_url))
    message("The resource is unavailable or has changed.")
    message("To download large files, try increasing the download timeout:")
    message("options(timeout = 600)")
    message("Original warning message:")
    message(x)
    return(NA)
  }
  )

  return(file_path)
}

# Extract the contents of a zip file
.unzip_file <- function(archive_path) {
  # Prepare temp dir
  tmp_dir <- tempdir()

  # Unpack zip file
  file_name <- utils::unzip(archive_path, list = TRUE)
  utils::unzip(archive_path, exdir = tmp_dir)

  # Get path(s) to csv file(s)
  file_path <- file.path(tmp_dir, file_name$Name)

  return(file_path)
}

#' Read a BIS data set from a local file
#'
#' @param file_path Character. Path to the CSV file to be read (usually obtained
#' via manual download from the BIS homepage).
#'
#' @return A tibble data frame.
#' @export
#'
#' @examples
#' \dontrun{
#' # Example 1: Read a locally stored CSV
#' df <- read_bis("WS_CBPOL_csv_flat.csv")
#'
#' # Example 2: Read a locally stored ZIP
#' df <- read_bis(.unzip_file("WS_CBPOL_csv_flat.zip"))
#' }
#'
read_bis <- function(file_path) {
  # Read data into tibble data frame
  tbl <- readr::read_csv(file_path, col_names = TRUE, show_col_types = FALSE,
                         na = c("", "NA", "NaN"),
                         col_types = readr::cols(.default = "c"))

  # Set column names
  names(tbl) <- .clean_names(names(tbl))

  # Convert observations to numeric
  tbl <- dplyr::mutate(tbl, obs_value = as.numeric(obs_value))

  return(tbl)
}

#' Retrieve a list of available BIS data sets
#'
#' @param base_url Character. URL of the BIS's homepage listing single file data
#' sets for download (optional).
#'
#' @return A tibble data frame.
#' @export
#'
#' @examples
#' \donttest{
#' ds <- get_datasets()
#' }
get_datasets <- function(
    base_url = "https://data.bis.org/bulkdownload") {
  tbl <- tryCatch({
    # Download webpage
    page  <- xml2::read_html(base_url)
    nodes <- rvest::html_nodes(page, xpath = "//a[contains(@href, 'zip')]")

    # Parse homepage: Get name, id, url
    item_name <- rvest::html_text(nodes)
    item_id   <- tools::file_path_sans_ext(
      basename(rvest::html_attr(nodes, "href"))
    )
    item_url  <- xml2::url_absolute(rvest::html_attr(nodes, "href"), base_url)

    # Keep only the flat items
    flat_items <- grep(".*flat.*", item_name)
    item_name  <- item_name[flat_items]
    item_id    <- item_id[flat_items]
    item_url   <- item_url[flat_items]

    # Return tibble data frame
    tbl <- dplyr::tibble(name = item_name,
                         id   = item_id,
                         url  = item_url)

    if (nrow(tbl) == 0) {
      message(paste("Unable to download and parse homepage:", base_url))
      message("The resource is unavailable or has changed.")
    }

    tbl
  },
  error = function(x) {
    message(paste("Unable to download and parse homepage:", base_url))
    message("The resource is unavailable or has changed.")
    message("Original error message:")
    message(x)
    return(NA)
  },
  warning = function(x) {
    message(paste("Unable to download and parse homepage:", base_url))
    message("The resource is unavailable or has changed.")
    message("Original warning message:")
    message(x)
    return(NA)
  }
  )

  return(tbl)
}

#' Download and parse a BIS data set
#'
#' @param item_url Character. URL of the data set to be imported (usually
#' obtained via \code{get_datasets()}).
#' @param ... Arguments passed to \code{download.file()} (e.g.
#' \code{quiet = TRUE}).
#'
#' @return A tibble data frame.
#' @export
#'
#' @examples
#' \donttest{
#' ds <- get_datasets()
#' df <- get_bis(ds$url[ds$id == "WS_CBPOL_csv_flat"])
#' }
get_bis <- function(item_url, ...) {
  try(zip_file_path <- .download_file(item_url, ...), TRUE)
  try(csv_file_path <- .unzip_file(zip_file_path), TRUE)
  try(return(read_bis(csv_file_path)), TRUE)
}
