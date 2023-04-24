
#include <R.h>
#include <Rinternals.h>

#ifdef __EMSCRIPTEN__
#include <emscripten.h>

/* Run Javascript using emscripten_run_script() */
#define js_exec_buffer_max 2048
#define js_exec(code, ...) ({{                                                 \
int ret = snprintf(httpuv_js_exec_buffer, js_exec_buffer_max, code, ## __VA_ARGS__);  \
if (ret < 0 || ret >= js_exec_buffer_max)                                      \
  error("problem writing JS exec buffer");                                     \
}                                                                              \
emscripten_run_script_int(httpuv_js_exec_buffer);})
char httpuv_js_exec_buffer[js_exec_buffer_max];
#endif

SEXP writeHttpuvWSResponse(SEXP handle, SEXP binary, SEXP type, SEXP message) {
#ifdef __EMSCRIPTEN__
  js_exec(
    "let handle = RObject.wrap(%d).toNumber();"
    "let binary = RObject.wrap(%d).toBoolean();"
    "let type = RObject.wrap(%d).toString();"
    "let message = RObject.wrap(%d).toString();"
    "chan.write({"
    "  type: '_webR_httpuv_WSResponse',"
    "  data: { handle, binary, type, message },"
    "});",
    (int) handle,
    (int) binary,
    (int) type,
    (int) message
  );
#endif
  return R_NilValue;
}

SEXP writeHttpuvTcpResponse(SEXP req, SEXP resp) {
#ifdef __EMSCRIPTEN__
  js_exec(
    "let req = RObject.wrap(%d);"
    "let resp = RObject.wrap(%d).toObject({ depth: 0 });"
    "let uuid = req.get('UUID').toString();"
    "chan.write("
    "  { type: '_webR_httpuv_TcpResponse', uuid, data: resp }"
    ");",
    (int) req,
    (int) resp
  );
#endif
    return R_NilValue;
}
