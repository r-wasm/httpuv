#include <stdio.h>
#include <map>
#include <iomanip>
#include <signal.h>
#include <errno.h>
#include <functional>
#include <memory>
#include <R.h>
#include "base64/base64.hpp"
#include "httpuv.h"

// [[Rcpp::export]]
std::string base64encode(const Rcpp::RawVector& x) {
  return b64encode(x.begin(), x.end());
}

static std::string allowed = ";,/?:@&=+$abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890-_.!~*'()";

bool isReservedUrlChar(char c) {
  switch (c) {
  case ';':
  case ',':
  case '/':
  case '?':
  case ':':
  case '@':
  case '&':
  case '=':
  case '+':
  case '$':
    return true;
  default:
    return false;
  }
}

bool needsEscape(char c, bool encodeReserved) {
  if (c >= 'a' && c <= 'z')
    return false;
  if (c >= 'A' && c <= 'Z')
    return false;
  if (c >= '0' && c <= '9')
    return false;
  if (isReservedUrlChar(c))
    return encodeReserved;
  switch (c) {
  case '-':
  case '_':
  case '.':
  case '!':
  case '~':
  case '*':
  case '\'':
  case '(':
  case ')':
    return false;
  }
  return true;
}

std::string doEncodeURI(std::string value, bool encodeReserved) {
  std::ostringstream os;
  os << std::hex << std::uppercase;
  for (std::string::const_iterator it = value.begin();
       it != value.end();
       it++) {
    
    if (!needsEscape(*it, encodeReserved)) {
      os << *it;
    } else {
      os << '%' << std::setw(2) << std::setfill('0') << static_cast<unsigned int>(static_cast<unsigned char>(*it));
    }
  }
  return os.str();
}

//' URI encoding/decoding
//' @export
// [[Rcpp::export]]
Rcpp::CharacterVector encodeURI(Rcpp::CharacterVector value) {
  Rcpp::CharacterVector out(value.size(), NA_STRING);
  
  for (int i = 0; i < value.size(); i++) {
    if (value[i] != NA_STRING) {
      std::string encoded = doEncodeURI(Rf_translateCharUTF8(value[i]), false);
      out[i] = Rf_mkCharCE(encoded.c_str(), CE_UTF8);
    }
  }
  return out;
}

//' @rdname encodeURI
//' @export
// [[Rcpp::export]]
Rcpp::CharacterVector encodeURIComponent(Rcpp::CharacterVector value) {
  Rcpp::CharacterVector out(value.size(), NA_STRING);
  
  for (int i = 0; i < value.size(); i++) {
    if (value[i] != NA_STRING) {
      std::string encoded = doEncodeURI(Rf_translateCharUTF8(value[i]), true);
      out[i] = Rf_mkCharCE(encoded.c_str(), CE_UTF8);
    }
  }
  return out;
}

int hexToInt(char c) {
  switch (c) {
  case '0': return 0;
  case '1': return 1;
  case '2': return 2;
  case '3': return 3;
  case '4': return 4;
  case '5': return 5;
  case '6': return 6;
  case '7': return 7;
  case '8': return 8;
  case '9': return 9;
  case 'A': case 'a': return 10;
  case 'B': case 'b': return 11;
  case 'C': case 'c': return 12;
  case 'D': case 'd': return 13;
  case 'E': case 'e': return 14;
  case 'F': case 'f': return 15;
  default: return -1;
  }
}

std::string doDecodeURI(std::string value, bool component) {
  std::ostringstream os;
  for (std::string::const_iterator it = value.begin();
       it != value.end();
       it++) {
    
    // If there aren't enough characters left for this to be a
    // valid escape code, just use the character and move on
    if (it > value.end() - 3) {
      os << *it;
      continue;
    }
    
    if (*it == '%') {
      char hi = *(++it);
      char lo = *(++it);
      int iHi = hexToInt(hi);
      int iLo = hexToInt(lo);
      if (iHi < 0 || iLo < 0) {
        // Invalid escape sequence
        os << '%' << hi << lo;
        continue;
      }
      char c = (char)(iHi << 4 | iLo);
      if (!component && isReservedUrlChar(c)) {
        os << '%' << hi << lo;
      } else {
        os << c;
      }
    } else {
      os << *it;
    }
  }
  
  return os.str();
}


//' @rdname encodeURI
//' @export
// [[Rcpp::export]]
Rcpp::CharacterVector decodeURI(Rcpp::CharacterVector value) {
  Rcpp::CharacterVector out(value.size(), NA_STRING);
  
  for (int i = 0; i < value.size(); i++) {
    if (value[i] != NA_STRING) {
      std::string decoded = doDecodeURI(Rcpp::as<std::string>(value[i]), false);
      out[i] = Rf_mkCharLenCE(decoded.c_str(), decoded.length(), CE_UTF8);
    }
  }
  
  return out;
}

//' @rdname encodeURI
//' @export
// [[Rcpp::export]]
Rcpp::CharacterVector decodeURIComponent(Rcpp::CharacterVector value) {
  Rcpp::CharacterVector out(value.size(), NA_STRING);
  
  for (int i = 0; i < value.size(); i++) {
    if (value[i] != NA_STRING) {
      std::string decoded = doDecodeURI(Rcpp::as<std::string>(value[i]), true);
      out[i] = Rf_mkCharLenCE(decoded.c_str(), decoded.length(), CE_UTF8);
    }
  }
  
  return out;
}

//[[Rcpp::export]]
std::string wsconn_address(Rcpp::IntegerVector handle) {
  std::ostringstream os;
  os << std::hex << "h0x" << handle;
  return os.str();
}

//' @keywords internal
//' @export
// [[Rcpp::export]]
void getRNGState() {
  GetRNGstate();
}