# Given the name or vector of names, returns a named vector reporting
# whether each exists and is a directory.
dir.exists <- function(x) {
  res <- file.exists(x) & file.info(x)$isdir
  stats::setNames(res, x)
}

compact <- function(x) {
  is_empty <- vapply(x, function(x) length(x) == 0, logical(1))
  x[!is_empty]
}

"%||%" <- function(a, b) if (!is.null(a)) a else b

"%:::%" <- function(p, f) {
  get(f, envir = asNamespace(p))
}

rule <- function(..., pad = "-") {
  if (nargs() == 0) {
    title <- ""
  } else {
    title <- paste0(..., " ")
  }
  width <- max(getOption("width") - nchar(title) - 1, 0)
  message(title, paste(rep(pad, width, collapse = "")))
}

# check whether the specified file ends with newline
ends_with_newline <- function(path) {
  conn <- file(path, open = "rb", raw = TRUE)
  on.exit(close(conn))
  seek(conn, where = -1, origin = "end")
  lastByte <- readBin(conn, "raw", n = 1)
  lastByte == 0x0a
}

render_template <- function(name, data = list()) {
  path <- system.file("templates", name, package = "devtools")
  template <- readLines(path)
  whisker::whisker.render(template, data)
}

is_installed <- function(pkg, version = 0) {
  installed_version <- tryCatch(utils::packageVersion(pkg), error = function(e) NA)
  !is.na(installed_version) && installed_version >= version
}

check_suggested <- function(pkg, version = NULL, compare = NA) {

  if (is.null(version)) {
    if (!is.na(compare)) {
      stop("Cannot set ", sQuote(compare), " without setting ",
           sQuote(version), call. = FALSE)
    }

    dep <- suggests_dep(pkg)

    version <- dep$version
    compare <- dep$compare
  }

  if (!is_installed(pkg) || !check_dep_version(pkg, version, compare)) {
    msg <- paste0(sQuote(pkg),
      if (is.na(version)) "" else paste0(" >= ", version),
      " must be installed for this functionality.")

    if (interactive()) {
      message(msg, "\nWould you like to install it?")
      if (menu(c("Yes", "No")) == 1) {
        install.packages(pkg)
      } else {
        stop(msg, call. = FALSE)
      }
    } else {
      stop(msg, call. = FALSE)
    }
  }
}

suggests_dep <- function(pkg) {

  suggests <- read_dcf(system.file("DESCRIPTION", package = "devtools"))$Suggests
  deps <- parse_deps(suggests)

  found <- which(deps$name == pkg)[1L]

  if (!length(found)) {
     stop(sQuote(pkg), " is not in Suggests: for devtools!", call. = FALSE)
  }
  deps[found, ]
}

read_dcf <- function(path) {
  fields <- colnames(read.dcf(path))
  as.list(read.dcf(path, keep.white = fields)[1, ])
}

write_dcf <- function(path, desc) {
  desc <- unlist(desc)
  # Add back in continuation characters
  desc <- gsub("\n[ \t]*\n", "\n .\n ", desc, perl = TRUE, useBytes = TRUE)
  desc <- gsub("\n \\.([^\n])", "\n  .\\1", desc, perl = TRUE, useBytes = TRUE)

  starts_with_whitespace <- grepl("^\\s", desc, perl = TRUE, useBytes = TRUE)
  delimiters <- ifelse(starts_with_whitespace, ":", ": ")
  text <- paste0(names(desc), delimiters, desc, collapse = "\n")

  # If the description file has a declared encoding, set it so nchar() works
  # properly.
  if ("Encoding" %in% names(desc)) {
    Encoding(text) <- desc[["Encoding"]]
  }

  if (substr(text, nchar(text), 1) != "\n") {
    text <- paste0(text, "\n")
  }

  cat(text, file = path)
}

dots <- function(...) {
  eval(substitute(alist(...)))
}

first_upper <- function(x) {
  substr(x, 1, 1) <- toupper(substr(x, 1, 1))
  x
}

download <- function(path, url, ...) {
  request <- httr::GET(url, ...)
  httr::stop_for_status(request)
  writeBin(httr::content(request, "raw"), path)
  path
}

download_text <- function(url, ...) {
  request <- httr::GET(url, ...)
  httr::stop_for_status(request)
  httr::content(request, "text")
}

last <- function(x) x[length(x)]

# Modified version of utils::file_ext. Instead of always returning the text
# after the last '.', as in "foo.tar.gz" => ".gz", if the text that directly
# precedes the last '.' is ".tar", it will include also, so
# "foo.tar.gz" => ".tar.gz"
file_ext <- function (x) {
    pos <- regexpr("\\.((tar\\.)?[[:alnum:]]+)$", x)
    ifelse(pos > -1L, substring(x, pos + 1L), "")
}

is_bioconductor <- function(x) {
  x$package != "BiocInstaller" && !is.null(x$biocviews)
}

trim_ws <- function(x) {
  gsub("^[[:space:]]+|[[:space:]]+$", "", x)
}

is_dir <- function(x) file.info(x)$isdir

indent <- function(x, spaces = 4) {
  ind <- paste(rep(" ", spaces), collapse = "")
  paste0(ind, gsub("\n", paste0("\n", ind), x, fixed = TRUE))
}

is_windows <- isTRUE(.Platform$OS.type == "windows")

all_named <- function (x) {
  if (length(x) == 0) return(TRUE)
  !is.null(names(x)) && all(names(x) != "")
}

make_function <- function (args, body, env = parent.frame()) {
  args <- as.pairlist(args)
  stopifnot(all_named(args), is.language(body))
  eval(call("function", args, body), env)
}

comp_lang <- function(x, y, idx = seq_along(y)) {
  if (is.symbol(x) || is.symbol(y)) {
    return(identical(x, y))
  }

  if (length(x) < length(idx)) return(FALSE)

  identical(x[idx], y[idx])
}

extract_lang <- function(x, f, ...) {
  recurse <- function(y) {
    unlist(compact(lapply(y, extract_lang, f = f, ...)), recursive = FALSE)
  }

  # if x matches predicate return it
  if (isTRUE(f(x, ...))) {
    return(x)
  }

  if (is.call(x)) {
    res <- recurse(x)[[1]]
    if (top_level_call <- identical(sys.call()[[1]], as.symbol("extract_lang"))
        && is.null(res)) {
      warning("Devtools is incompatible with the current version of R. `load_all()` may function incorrectly.")
    }
    return(res)
  }

  NULL
}

modify_lang <- function(x, f, ...) {
  recurse <- function(x) {
    lapply(x, modify_lang, f = f, ...)
  }

  x <- f(x, ...)

  if (is.call(x)) {
    as.call(recurse(x))
  } else if (is.function(x)) {
     formals(x) <- modify_lang(formals(x), f, ...)
     body(x) <- modify_lang(body(x), f, ...)
  } else {
    x
  }
}

strip_internal_calls <- function(x, package) {
  if (is.call(x) && identical(x[[1L]], as.name(":::")) && identical(x[[2L]], as.name(package))) {
    x[[3L]]
  } else {
    x
  }
}

sort_ci <- function(x) {
  withr::with_collate("C", x[order(tolower(x), x)])
}

comma <- function(x, at_most = 20) {
  if (length(x) > at_most) {
    x <- c(x[seq_len(at_most)], "...")
  }
  paste(x, collapse = ", ")
}
