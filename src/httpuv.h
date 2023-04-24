#ifndef HTTPUV_HPP
#define HTTPUV_HPP

#include <Rcpp.h>
#include <Rinternals.h>

std::string doEncodeURI(std::string value, bool encodeReserved);
std::string doDecodeURI(std::string value, bool component);

#endif