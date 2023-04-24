# Httpuv shim for webR

A minimal shim package for the [httpuv](https://cran.r-project.org/web/packages/httpuv/index.html) package for webR.

This webR package is based on the original httpuv package for R, heavily modified to remove the original HTTP and WS server infrastructure. Instead, relevant callbacks to service HTTP and WS requests are made available for use through webR and a JavaScript service worker.
