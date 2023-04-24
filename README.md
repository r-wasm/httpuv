# Httpuv shim for webR

A minimal shim package for the [httpuv](https://cran.r-project.org/web/packages/httpuv/index.html) package for webR.

This webR package is based on the original httpuv package for R, heavily modified to remove the original HTTP and WS server infrastructure. Instead, relevant callbacks to service HTTP and WS requests are made available for use in webR, so that they can be invoked using a JavaScript service worker.

## Request functions
When a httpuv server is created, the following service functions are set in the global R options,

Name | Arguments |Description
-----|----|------------
`webr_httpuv_onRequest`| `(req)` | To be called with a HTTP request.
`webr_httpuv_onWSOpen` | `(handle, req)` | To be called when a WebSocket is opened.
`webr_httpuv_onWSMessage` | `(handle, binary, message)` | To be called when a WebSocket message is transmitted.

Request objects `req` follow the structure used in the original httpuv package, with the exception that HTTP requests should also include an additional element named `uuid` containing a universally unique identifier string. The HTTP response will contain the same UUID as an aid to matching requests with responses.

At the moment, WS requests should always be sent with a `handle` argument of `1`.

## Response format

HTTP and WS responses are transmitted over the established webR communication channel.

Message Type | Description
-------------|------------
`_webR_httpuv_TcpResponse` | Response to a HTTP request with result contained in the `data` property.
`_webR_httpuv_WSResponse`  | A WS message transmitted from R with message content contained in the `data` property.

## Limitations
Currently only one httpuv server can be created at a time. The server will always have a `handle` value of `1`.
