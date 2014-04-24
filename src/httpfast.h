#include <stdarg.h>


static inline const char *
httpfast_parse_params(const char *str, size_t str_len,
	int (*on_param)(void *uobj,
		const char *name, size_t name_len,
		const char *value, size_t value_len), void *uobj)
{
	enum {
		name,
		value
	} state = name;

	const char *p, *pe;

	const char *nb, *vb;
	size_t nl, vl;

	for (nb = p = str, pe = str + str_len; p < pe; p++) {
		char c = *p;
		switch(state) {
			case name:
				if (c == '=') {
					nl = p - nb;
					vb = p + 1;
					state = value;
					break;
				}

				if (c == '&') {
					if (p == nb) {
						nb = p + 1;
						break;
					}
					nl = p - nb;
					if (on_param(uobj, nb, nl, "", 0) != 0)
						return p;
					nb = p + 1;
					break;
				}
				break;
			case value:
				if (c != '&')
					break;
				vl = p - vb;

				if (vl || nl)
					if (on_param(uobj, nb, nl, vb, vl) != 0)
						return p;

				nb = p + 1;
				state = name;
				break;
		}
	}
	switch(state) {
		case value:
			vl = pe - vb;
			if (vl || nl)
				on_param(uobj, nb, nl, vb, vl);
			break;
		case name:
			nl = pe - nb;
			if (nl)
				on_param(uobj, nb, nl, "", 0);
			break;

	}

	return NULL;
}


struct parse_http_events {
    void (*on_error)(void *uobj, int code, const char *fmt, va_list ap);
    void (*on_warn)(void *uobj, int code, const char *fmt, va_list ap);

    int (*on_header)(void *uobj,
                        const char *name, size_t name_len,
                        const char *value, size_t value_len,
                        int is_continuation);
    int (*on_body)(void *uobj, const char *body, size_t body_len);

    int (*on_request_line)(
        void *uobj,
        const char *method,
        size_t method_len,
        const char *path,
        size_t path_len,

        const char *query,
        size_t query_len,

        int http_major,
        int http_minor
    );
    int (*on_response_line)(
        void *uobj,
        unsigned code,
        const char *reason,
        size_t reason_len,
        int http_major,
        int http_minor
    );
};


enum {
    HTTP_PARSER_WRONG_ARGUMENTS = -512,
    HTTP_PARSER_IS_NOT_REALIZED_YET,

    HTTP_PARSER_BROKEN_REQUEST_LINE,
    HTTP_PARSER_BROKEN_RESPONSE_LINE,

    HTTP_PARSER_BROKEN_LINEDIVIDER,
    HTTP_PARSER_BROKEN_HEADER
};


static inline
void emit_errwarn(
    void (*cb)(void *uobj, int code, const char *fmt, va_list ap),

               void *uobj, int code, const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    if (cb)
        cb(uobj, code, fmt, ap);
    va_end(ap);
}

/**
 * parse http request (header)
 */

static inline const char *
httpfast_parse(
    const char *str, size_t len,
    const struct parse_http_events *event,
    void *uobj)
{
    #define errorf(code, fmt...)                                    \
        do {                                                        \
            emit_errwarn(event->on_error, uobj, code, fmt);         \
            return NULL;                                            \
        } while(0)

    #define warnf(code, fmt...)                                     \
        do {                                                        \
            emit_errwarn(event->on_warn, uobj, code, fmt);          \
        } while(0)

    #define emit_event(name, arg...)                                \
        do {                                                        \
            if (event->name) {                                      \
                if (event->name(uobj, arg) != 0) {                  \
                    return NULL;                                    \
                }                                                   \
            }                                                       \
        } while(0)



    static const char lowcase[] =
        "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0"
        "\0\0\0\0\0\0\0\0\0\0\0\0\0-\0\0" "0123456789\0\0\0\0\0\0"
        "\0abcdefghijklmnopqrstuvwxyz\0\0\0\0_"
        "\0abcdefghijklmnopqrstuvwxyz\0\0\0\0\0"
        "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0"
        "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0"
        "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0"
        "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0";


    if (event->on_request_line && event->on_response_line)
        errorf(
            HTTP_PARSER_WRONG_ARGUMENTS,
            "Only one of handlers must be defined: "
            "on_request_line or on_response_line"
        );

    if (len == 0)
        errorf(HTTP_PARSER_WRONG_ARGUMENTS, "Empty input string");

    enum {
        CR      =   13,
        LF      =   10,
        TAB     =   9,
    };

    typedef enum {
                    request_line,
                    method,
                    path,
                    query,
                    rhttp,

                    response_line,
                    status_sp,
                    status,
                    message_sp,
                    message,

                    cr,
                    lf,

                    header_next,
                    header_name,
                    header_sp,
                    header_cl_sp,
                    header_val,
    } pstate;

    pstate state;
    if (event->on_request_line) {
        state = request_line;
    } else if (event->on_response_line) {
        state = response_line;
    } else {
        state = header_next;
    }

    const char *p,      /* pointer */
            *pe,        /* end of data */
            *tb,        /* begin of token */

            *ptb,       /* begin of prev token */
            *pptb       /* begin of prev prev token */
    ;
    size_t tl;          /* length of token */
    size_t ptl;         /* length of prev token */
    size_t pptl;        /* length of prev prev token */
    int h_is_c;         /* header is continuation */
    int headers = 0;    /* how many headers found */
    char c;

    char major, minor;
    unsigned code;

    for (p = str, pe = str + len; p < pe; p++) {
        redo:
        c = *p;
        switch(state) {
            /*********************** request line ************************/
            case request_line:
                /* 'GET / HTTP/1.0' - min = 14 */
                if (pe - p < 14) {
                    errorf(HTTP_PARSER_BROKEN_REQUEST_LINE,
                        "Broken request line"
                    );
                }
                state = method;
                tb = p;
                goto redo;

            case method:
                if (c != ' ' && c != '\t')
                    break;
                pptb = tb;
                pptl = p - tb;
                tb = p + 1;
                state = path;
                break;



            case path:
                if (c == '?') {
                    state = query;

                    ptb = tb;
                    ptl = p - tb;

                    tb = p + 1;
                    break;
                }

                if (c == ' ' || c == '\t') {
                    state = rhttp;
                    ptl = p - tb;
                    ptb = tb;
                    tb = p;
                    tl = 0;
                    break;
                }
                break;

            case query:
                if (c != ' ' && c != '\t')
                    break;
                tl = p - tb;
                state = rhttp;
                break;


            case rhttp:
                /* H T T P / 1 . 0 */
                /* 0 1 2 3 4 5 6 7 */
                if (pe - p < 8) {
                    errorf(HTTP_PARSER_BROKEN_REQUEST_LINE,
                        "Too short request line"
                    );
                }
                if (memcmp(p, "HTTP/", 5) != 0 || p[6] != '.') {
                    errorf(HTTP_PARSER_BROKEN_REQUEST_LINE,
                        "Broken protocol section in request line"
                    );
                }
                if (p[5] > '9' || p[5] < '0' || p[7] > '9' || p[7] < '0') {
                    errorf(HTTP_PARSER_BROKEN_REQUEST_LINE,
                        "Wrong protocol version in request line"
                    );
                }
                emit_event(on_request_line,
                    pptb, pptl,
                    ptb, ptl,
                    tb, tl,
                    (int)(p[5] - '0'),
                    (int)(p[7] - '0')
                );

                p += 7;


                state = cr;
                break;


            /************************* response line **********************/
            case response_line:
                if (pe - p < 15) {
                    errorf(HTTP_PARSER_BROKEN_RESPONSE_LINE,
                        "Too short response line"
                    );
                }
                if (memcmp(p, "HTTP/", 5) != 0 && p[6] != '.') {
                    errorf(HTTP_PARSER_BROKEN_RESPONSE_LINE,
                        "Protocol section is not valid in response line"
                    );
                }
                if (p[5] > '9' || p[5] < '0' || p[7] > '9' || p[7] < 0) {
                    errorf(HTTP_PARSER_BROKEN_RESPONSE_LINE,
                        "Wrong http version number: %c.%c in response line",
                        p[5],
                        p[7]
                    );
                }

                if (p[8] != ' ' && p[8] != '\t') {
                    errorf(HTTP_PARSER_BROKEN_RESPONSE_LINE,
                        "Broken protocol section in response line: %*s",
                        9, p
                    );
                }

                major = p[5] - '0';
                minor = p[7] - '0';

                p += 8 - 1; /* 'HTTP/x.y' - cycle increment */
                tb = p + 1;
                state = status_sp;
                break;

            case status_sp:
                if (c == ' ' || c == '\t')
                    break;

                state = status;
                tb = p;
                code = 0;

            case status:
                if (c == ' ' || c == '\t') {
                    tb = p;
                    state = message_sp;
                    break;

                }
                if (c > '9' || c < '0') {
                    errorf(HTTP_PARSER_BROKEN_RESPONSE_LINE,
                        "Non-digit symbol in code in response line: %02X", c);
                }
                code *= 10;
                code += c - '0';
                break;

            case message_sp:
                if (c == ' ' || c == '\t')
                    break;
                tb = p;
                state = message;

            case message:
                if (c != CR && c != LF)
                    break;
                tl = p - tb;

                emit_event(on_response_line, code, tb, tl, major, minor);
                state = cr;
                goto redo;



            /************************ headers *****************************/
            case cr:
                if (c == LF) {
                    state = header_next;
                    break;
                }

                if (c != CR) {
                    errorf(HTTP_PARSER_BROKEN_LINEDIVIDER,
                        "Expected CR or LF, received: %02x",
                        c
                    );
                }
                state = lf;
                break;

            case lf:
                if (c != LF) {
                        errorf(HTTP_PARSER_BROKEN_LINEDIVIDER,
                            "Expected LF, received: %02x",
                            c
                        );
                }
                state = header_next;
                break;


            case header_next:
                if (c == ' ' || c == '\t') {
                    if (!headers) {
                        errorf(HTTP_PARSER_BROKEN_HEADER,
                            "Continuation for header at the first header"
                        );
                    }
                    state = header_cl_sp;
                    h_is_c = 1;
                    break;
                }
                if (c == LF) {
                    emit_event(on_body, p + 1, pe - p - 1);
                    return p + 1;
                }
                if (c == CR) {
                    if (p < pe - 1) {
                        if (p[1] == LF) {
                            emit_event(on_body, p + 2, pe - p - 2);
                        } else {
                            errorf(HTTP_PARSER_BROKEN_HEADER,
                                "Unexpected sequience: CR, %02X",
                                p[1]
                            );
                        }
                    } else {
                        emit_event(on_body, "", 0);
                    }
                    return p + 1;
                }
                if (!lowcase[(int)c]) {
                    errorf(HTTP_PARSER_BROKEN_HEADER,
                        "Broken first symbol of header: %02X",
                        c
                    );
                }
                headers++;
                tb = p;
                state = header_name;
                break;

            case header_name:
                if (lowcase[(int)c])
                    break;

                h_is_c = 0;
                if (c == ':') {
                    tl = p - tb;
                    state = header_cl_sp;
                    break;
                }

                if (c == ' ' || c == TAB) {
                    tl = p - tb;
                    state = header_sp;
                    break;
                }

                if (c == CR || c == LF) {
                    state = header_next;
                    break;
                }

                errorf(HTTP_PARSER_BROKEN_HEADER,
                    "Unexpected symbol in header name: %02X",
                    c
                );
            /* header value */
            case header_val:
                if (c != CR && c != LF) {
                    break;
                }
                ptl = p - ptb;
                emit_event(on_header, tb, tl, ptb, ptl, h_is_c);
                state = cr;
                goto redo;

            /* spaces between header ':' and value */
            case header_cl_sp:
                if (c == TAB || c == ' ')
                    break;

                if (c == CR || c == LF) {
                    emit_event(on_header, tb, tl, "", 0, h_is_c);
                    state = cr;
                    goto redo;
                }


                ptb = p;
                state = header_val;
                break;

            /* spaces between headername and ':' */
            case header_sp:
                if (c == TAB || c == ' ')
                    break;
                if (c == ':') {
                    state = header_cl_sp;
                    break;
                }
                errorf(HTTP_PARSER_BROKEN_HEADER,
                    "Expected ':', received '%c' (%02x)",
                    c,
                    c
                );

        }
    }

    /* unfinished parsing */
    switch(state) {
        case header_val:
            ptl = pe - ptb;
            emit_event(on_header, tb, tl, ptb, ptl, h_is_c);
            break;

        case method:
        case path:
            errorf(HTTP_PARSER_BROKEN_REQUEST_LINE,
                "Unexpected EOF while parsing request line"
            );

        case message:
            tl = pe - tb;
            emit_event(on_response_line, code, tb, tl, major, minor);
            break;

        case message_sp:
            emit_event(on_response_line, code, "", 0, major, minor);
            break;

        case status_sp:
        case status:
            errorf(HTTP_PARSER_BROKEN_RESPONSE_LINE,
                "Unexpected EOF while parsing response line"
            );
        default:
            break;

    }

    return str;

    #undef warnf
    #undef errorf
    #undef emit_event
}

