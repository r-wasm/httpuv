#' @useDynLib httpuv
NULL

.globals <- new.env()

#' @export
WebSocket <- R6Class(
  'WebSocket',
  public = list(
    initialize = function(handle, req) {
      self$handle <- handle
      self$request <- req
    },
    onMessage = function(func) {
      self$messageCallbacks <- c(self$messageCallbacks, func)
    },
    onClose = function(func) {
      self$closeCallbacks <- c(self$closeCallbacks, func)
    },
    send = function(message) {
      if (is.null(self$handle))
        return()
      
      if (is.raw(message))
        .Call("writeHttpuvWSResponse", self$handle, TRUE, 'websocket.send', message)
      else {
        # TODO: Ensure that message is UTF-8 encoded
        .Call("writeHttpuvWSResponse", self$handle, FALSE, 'websocket.send', as.character(message))
      }
    },
    close = function(code = 1000L, reason = "") {
      if (is.null(self$handle))
        return()
      .Call("writeHttpuvWSResponse", self$handle, TRUE, 'websocket.close', reason)
      self$handle <- NULL
    },
    
    handle = NULL,
    messageCallbacks = list(),
    closeCallbacks = list(),
    request = NULL
  )
)

#' @importFrom promises promise then finally is.promise %...>% %...!%
AppWrapper <- R6Class(
  'AppWrapper',
  private = list(
    app = NULL,                    # List defining app
    wsconns = NULL,                # An environment containing websocket connections
    supportsOnHeaders = NULL       # Logical
  ),
  public = list(
    initialize = function(app) {
      if (is.function(app))
        private$app <- list(call=app)
      else
        private$app <- app
      
      # private$app$onHeaders can error (e.g. if private$app is a reference class)
      private$supportsOnHeaders <- isTRUE(try(!is.null(private$app$onHeaders), silent=TRUE))
      
      # staticPaths are saved in a field on this object, because they are read
      # from the app object only during initialization. This is the only time
      # it makes sense to read them from the app object, since they're
      # subsequently used on the background thread, and for performance
      # reasons it can't call back into R. Note that if the app object is a
      # reference object and app$staticPaths is changed later, it will have no
      # effect on the behavior of the application.
      #
      # If private$app is a reference class, accessing private$app$staticPaths
      # can error if not present. Saving here in a separate var because R CMD
      # check complains if you compare class(x) with a string.
      try_obj_class <- class(try(private$app$staticPaths, silent = TRUE))
      if (try_obj_class == "try-error" || is.null(private$app$staticPaths)) {
        self$staticPaths <- list()
      } else {
        self$staticPaths <- normalizeStaticPaths(private$app$staticPaths)
      }
      
      try_obj_class <- class(try(private$app$staticPathOptions, silent = TRUE))
      if (try_obj_class == "try-error" || is.null(private$app$staticPathOptions)) {
        # Use defaults
        self$staticPathOptions <- staticPathOptions()
      } else if (inherits(private$app$staticPathOptions, "staticPathOptions")) {
        self$staticPathOptions <- normalizeStaticPathOptions(private$app$staticPathOptions)
      } else {
        stop("staticPathOptions must be an object of class staticPathOptions.")
      }
      
      private$wsconns <- new.env(parent = emptyenv())
    },
    onHeaders = function(req) {
      if (!private$supportsOnHeaders)
        return(NULL)
      
      private$app$onHeaders(req)
    },
    onBodyData = function(req, bytes) {
      if (is.null(req$.bodyData))
        req$.bodyData <- file(open='w+b', encoding='UTF-8')
      writeBin(bytes, req$.bodyData)
    },
    call = function(req) {
      resp <- if (is.null(private$app$call)) {
        list(
          status = 404L,
          headers = list(
            "Content-Type" = "text/plain"
          ),
          body = "404 Not Found\n"
        )
      } else {
        url <- req$PATH_INFO
        file_resp <- NULL
        for (name in names(private$app$staticPaths)) {
          value <- private$app$staticPaths[[name]]
          if (startsWith(url, name)) {
            path <- gsub(gsub("\\/$", "", name), value$path, url)
            if (endsWith(path, '/')) {
              path <- path + "index.html"
            }
            if (file.exists(path)) {
              woff <- c(woff2 = "application/font-woff2")
              file_resp <- list(
                status = 200L,
                headers = list(
                  "Content-Type" = mime::guess_type(path, mime_extra = woff)
                ),
                body = readBin(path, "raw", n = file.info(path)$size, size = 1L)
              )
              break
            }
            if (!value$options$fallthrough) {
              file_resp <- list(
                status = 404L,
                headers = list(
                  "Content-Type" = "text/plain"
                ),
                body = "404 Not Found\n"
              )
              break
            }
          }
        }
        if (is.null(file_resp)) {
          private$app$call(req)
        } else {
          file_resp
        }
      }
      
      clean_up <- function() {
        if (!is.null(req$.bodyData)) {
          close(req$.bodyData)
        }
        req$.bodyData <- NULL
      }
      
      if (is.promise(resp)) {
        # Slower path if resp is a promise
        resp <- resp %...>% .Call("writeHttpuvTcpResponse", req, .)
        finally(resp, clean_up)
        
      } else {
        # Fast path if resp is a regular value
        on.exit(clean_up())
        .Call("writeHttpuvTcpResponse", req, resp)
      }
      
      invisible()
    },
    onWSOpen = function(handle, req) {
      ws <- WebSocket$new(handle, req)
      private$wsconns[[wsconn_address(handle)]] <- ws
      result <- try(private$app$onWSOpen(ws))
      
      # If an unexpected error happened, just close up
      if (inherits(result, 'try-error')) {
        ws$close(1011, "Error in onWSOpen")
      }
    },
    onWSMessage = function(handle, binary, message) {
      for (handler in private$wsconns[[wsconn_address(handle)]]$messageCallbacks) {
        result <- try(handler(binary, message))
        if (inherits(result, 'try-error')) {
          private$wsconns[[wsconn_address(handle)]]$close(1011, "Error executing onWSMessage")
          return()
        }
      }
    },
    onWSClose = function(handle) {
      ws <- private$wsconns[[wsconn_address(handle)]]
      ws$handle <- NULL
      rm(list = handle, envir = private$wsconns)
      
      for (handler in ws$closeCallbacks) {
        handler()
      }
    },
    
    staticPaths = NULL,            # List of static paths
    staticPathOptions = NULL       # StaticPathOptions object
  )
)

#' @keywords internal
#' @importFrom R6 R6Class
Server <- R6Class("Server",
  cloneable = FALSE,
  public = list(
    stop = function() {
      if (!private$running) return(invisible())

      options(webr_httpuv_onWSMessage = NULL)
      options(webr_httpuv_onWSOpen = NULL)
      options(webr_httpuv_onRequest = NULL)

      private$running <- FALSE
      invisible()
    },
    isRunning = function() {
      private$running
    },
    getStaticPaths = function() { list() },
    setStaticPath = function(..., .list = NULL) { },
    removeStaticPath = function(path) { },
    getStaticPathOptions = function() { list() },
    setStaticPathOption = function(..., .list = NULL) {}
  ),
  private = list(
    appWrapper = NULL,
    handle = NULL,
    running = FALSE
  )
)

#' @keywords internal
WebServer <- R6Class("WebServer",
  cloneable = FALSE,
  inherit = Server,
  public = list(
    initialize = function(host, port, app, quiet = FALSE) {
      private$host <- host
      private$port <- port
      private$appWrapper <- AppWrapper$new(app)
      private$handle <- 1
      options(webr_httpuv_onWSMessage = private$appWrapper$onWSMessage)
      options(webr_httpuv_onWSOpen = private$appWrapper$onWSOpen)
      options(webr_httpuv_onRequest = private$appWrapper$call)
      private$running <- TRUE
    },
    getHost = function() {
      private$host
    },
    getPort = function() {
      private$port
    }
  ),
  private = list(
    host = NULL,
    port = NULL
  )
)

# Shiny blocks and calls this service() function in a loop.
# We dispatch any awaiting webR channel messages here, allowing webR to
# respond to communication from a Shiny application. Messages of type stdin
# can't be handled here, so are dropped.
# TODO: Ignore or re-queue stdin messages so that they are handled properly
#       when Shiny is no longer blocking and control is returned to the REPL.
#' @export
#' @importFrom later run_now
#' @importFrom webr eval_js
service <- function(timeoutMs = 0) {
  run_now()
  eval_js("
    let msg = chan.read();
    while (msg.type === 'stdin') msg = chan.read();
    dispatch(msg);
  ")
  TRUE
}

#' @export
startServer <- function(host, port, app, quiet = FALSE) {
  WebServer$new(host, port, app, quiet)
}

#' @export
runServer <- function(host, port, app, interruptIntervalMs = NULL) {
  server <- startServer(host, port, app)
  on.exit(stopServer(server))
  service(0)
}

#' @export
stopServer <- function(server) {
  if (!inherits(server, "Server")) {
    stop("Object must be an object of class Server.")
  }
  server$stop()
}

#' @export
ipFamily <- function(ip) {
  4
}

#' @export
interrupt <- function() {
  .globals$paused <- TRUE
}

#' @export
rawToBase64 <- function(x) {
  base64encode(x)
}
