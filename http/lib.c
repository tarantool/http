
/*
 * Redistribution and use in source and binary forms, with or
 * without modification, are permitted provided that the following
 * conditions are met:
 *
 * 1. Redistributions of source code must retain the above
 *    copyright notice, this list of conditions and the
 *    following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above
 *    copyright notice, this list of conditions and the following
 *    disclaimer in the documentation and/or other materials
 *    provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY <COPYRIGHT HOLDER> ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
 * TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL
 * <COPYRIGHT HOLDER> OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
 * INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
 * BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 * LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF
 * THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "tpleval.h"
#include "httpfast.h"

static void
tpl_term(int type, const char *str, size_t len, void *data)
{
	luaL_Buffer *b = (luaL_Buffer *)data;
	size_t i;

	switch(type) {
		case TPE_TEXT:
			luaL_addstring(b, "_i(\"");
			for(i = 0; i < len; i++) {
				switch(str[i]) {
					case '\n':
						luaL_addstring(b,
								"\\n\" ..\n\"");
						break;
					case '\r':
						luaL_addstring(b,
								"\\r");
						break;
					case '"':
						luaL_addchar(b, '\\');
					default:
						luaL_addchar(b, str[i]);
						break;
				}
			}
			luaL_addstring(b, "\") ");
			break;
		case TPE_LINECODE:
		case TPE_MULTILINE_CODE:
			/* _i one line */
			if (len > 1 && str[0] == '=' && str[1] == '=') {
				luaL_addstring(b, "_i(");
				luaL_addlstring(b, str + 2, len - 2);
				luaL_addstring(b, ") ");
				break;
			}
			/* _q one line */
			if (len > 0 && str[0] == '=') {
				luaL_addstring(b, "_q(");
				luaL_addlstring(b, str + 1, len - 1);
				luaL_addstring(b, ") ");
				break;
			}
			luaL_addlstring(b, str, len);
			luaL_addchar(b, ' ');
			break;
		default:
			abort();
	}
}

static int
lbox_httpd_escape_html(struct lua_State *L)
{
	int idx  = lua_upvalueindex(1);

	int i, top = lua_gettop(L);
	lua_rawgeti(L, idx, 1);

	luaL_Buffer b;
	luaL_buffinit(L, &b);

	if (lua_isnil(L, -1)) {
		luaL_addstring(&b, "");
	} else {
		luaL_addvalue(&b);
	}

	for (i = 1; i <= top; i++) {
		if (lua_isnil(L, i)) {
			luaL_addstring(&b, "nil");
			continue;
		}
		const char *s = lua_tostring(L, i);
		for (; *s; s++) {
			switch(*s) {
				case '&':
					luaL_addstring(&b, "&amp;");
					break;
				case '<':
					luaL_addstring(&b, "&lt;");
					break;
				case '>':
					luaL_addstring(&b, "&gt;");
					break;
				case '"':
					luaL_addstring(&b, "&quot;");
					break;
				case '\'':
					luaL_addstring(&b, "&#39;");
					break;
				default:
					luaL_addchar(&b, *s);
					break;
			}
		}
	}

	luaL_pushresult(&b);
	lua_rawseti(L, idx, 1);
	return 0;
}

static int
lbox_httpd_immediate_html(struct lua_State *L)
{
	int idx  = lua_upvalueindex(1);

	int k = 0;
	int i, top = lua_gettop(L);

	lua_rawgeti(L, idx, 1);
	if (lua_isnil(L, -1)) {
		lua_pop(L, 1);
	} else {
		++k;
	}

	lua_checkstack(L, top - 1);
	for (i = 1; i <= top; i++) {
		if (lua_isnil(L, i)) {
			lua_pushliteral(L, "nil");
			++k;
			continue;
		}
		lua_pushvalue(L, i);
		++k;
	}

	lua_concat(L, k);
	lua_rawseti(L, idx, 1);
	return 0;
}

static int
lbox_httpd_template(struct lua_State *L)
{
	int top = lua_gettop(L);
	if (top == 1)
		lua_newtable(L);
	if (top != 2)
		luaL_error(L, "box.httpd.template: absent or spare argument");
	if (!lua_istable(L, 2))
		luaL_error(L, "usage: box.httpd.template(tpl, { var = val })");


	lua_newtable(L);	/* 3. results (closure table) */

	lua_pushnil(L);		/* 4. place for prepared html */

	lua_pushnil(L);		/* 5. place for process function */

	lua_pushvalue(L, 3);	/* _q */
	lua_pushcclosure(L, lbox_httpd_escape_html, 1);

	lua_pushvalue(L, 3);	/* _i */
	lua_pushcclosure(L, lbox_httpd_immediate_html, 1);

	size_t len;
	const char *str = lua_tolstring(L, 1, &len);

	luaL_Buffer b;
	luaL_buffinit(L, &b);

	luaL_addstring(&b, "return function(_q, _i");

	lua_pushnil(L);
	while(lua_next(L, 2) != 0) {
		size_t l;
		const char *s = lua_tolstring(L, -2, &l);

		/* TODO: check argument for lua syntax */

		luaL_addstring(&b, ", ");
		luaL_addlstring(&b, s, l);

		lua_pushvalue(L, -2);
		lua_remove(L, -3);
	}

	luaL_addstring(&b, ") ");

	tpe_parse(str, len, tpl_term, &b);

	luaL_addstring(&b, " end");

	luaL_pushresult(&b);

	lua_replace(L, 4);

	lua_pushvalue(L, 4);

	/* compile */
	if (luaL_dostring(L, lua_tostring(L, 4)) != 0)
		lua_error(L);

	lua_replace(L, 5);	/* process function */

	/* stack:
	   1 - user's template,
	   2 - user's arglist
	   3 - closure table
	   4 - prepared html
	   5 - compiled function
	   ... function arguments
	   */

	if (lua_pcall(L, lua_gettop(L) - 5, 0, 0) != 0) {
		lua_getfield(L, -1, "match");

		lua_pushvalue(L, -2);
		lua_pushliteral(L, ":(%d+):(.*)");
		lua_call(L, 2, 2);

		lua_getfield(L, -1, "format");
		lua_pushliteral(L, "box.httpd.template: users template:%s: %s");
		lua_pushvalue(L, -4);
		lua_pushvalue(L, -4);
		lua_call(L, 3, 1);

		lua_error(L);
	}

	lua_pushnumber(L, 1);
	lua_rawget(L, 3);
	lua_replace(L, 3);

	return 2;
}

static void
http_parser_on_error(void *uobj, int code, const char *fmt, va_list ap)
{
	struct lua_State *L = (struct lua_State *)uobj;
	char estr[256];
	vsnprintf(estr, 256, fmt, ap);
	lua_pushliteral(L, "error");
	lua_pushstring(L, estr);
	lua_rawset(L, -4);

	(void)code;
}

static int
http_parser_on_header(void *uobj, const char *name, size_t name_len,
		      const char *value, size_t value_len, int is_continuation)
{
	struct lua_State *L = (struct lua_State *)uobj;


	luaL_Buffer b;
	luaL_buffinit(L, &b);
	size_t i;
	for (i = 0; i < name_len; i++) {
		switch(name[i]) {
			case 'A' ... 'Z':
				luaL_addchar(&b, name[i] - 'A' + 'a');
				break;
			default:
				luaL_addchar(&b, name[i]);
		}
	}
	luaL_pushresult(&b);

	if (is_continuation) {
		lua_pushvalue(L, -1);
		lua_rawget(L, -3);

		luaL_Buffer b;
		luaL_buffinit(L, &b);
		luaL_addvalue(&b);
		luaL_addchar(&b, ' ');
		luaL_addlstring(&b, value, value_len);
		luaL_pushresult(&b);

	} else {
		lua_pushvalue(L, -1);
		lua_rawget(L, -3);

		if (lua_isnil(L, -1)) {
			lua_pop(L, 1);
			lua_pushlstring(L, value, value_len);
		} else {
			luaL_Buffer b;
			luaL_buffinit(L, &b);
			luaL_addvalue(&b);
			luaL_addchar(&b, ',');
			luaL_addchar(&b, ' ');
			luaL_addlstring(&b, value, value_len);
			luaL_pushresult(&b);
		}
	}

	lua_rawset(L, -3);

	return 0;
}

	static int
http_parser_on_body(void *uobj, const char *body, size_t body_len)
{
	struct lua_State *L = (struct lua_State *)uobj;
	lua_pushliteral(L, "body");
	lua_pushlstring(L, body, body_len);
	lua_rawset(L, -4);
	return 0;
}

static int
http_parser_on_request_line(void *uobj, const char *method, size_t method_len,
			    const char *path, size_t path_len,
			    const char *query, size_t query_len,
			    int http_major, int http_minor)
{
	struct lua_State *L = (struct lua_State *)uobj;

	lua_pushliteral(L, "method");
	lua_pushlstring(L, method, method_len);
	lua_rawset(L, -4);

	lua_pushliteral(L, "path");
	lua_pushlstring(L, path, path_len);
	lua_rawset(L, -4);

	lua_pushliteral(L, "query");
	lua_pushlstring(L, query, query_len);
	lua_rawset(L, -4);

	lua_pushliteral(L, "proto");
	lua_newtable(L);

	lua_pushnumber(L, 1);
	lua_pushnumber(L, http_major);
	lua_rawset(L, -3);

	lua_pushnumber(L, 2);
	lua_pushnumber(L, http_minor);
	lua_rawset(L, -3);

	lua_rawset(L, -4);

	return 0;
}

static int
http_parser_on_response_line(void *uobj, unsigned code,
			     const char *reason, size_t reason_len,
			     int http_major, int http_minor)
{
	struct lua_State *L = (struct lua_State *)uobj;

	lua_pushliteral(L, "proto");
	lua_newtable(L);

	lua_pushnumber(L, 1);
	lua_pushnumber(L, http_major);
	lua_rawset(L, -3);

	lua_pushnumber(L, 2);
	lua_pushnumber(L, http_minor);
	lua_rawset(L, -3);

	lua_rawset(L, -4);

	lua_pushliteral(L, "reason");
	lua_pushlstring(L, reason, reason_len);
	lua_rawset(L, -4);

	lua_pushliteral(L, "status");
	lua_pushnumber(L, code);
	lua_rawset(L, -4);

	return 0;
}

static int
lbox_http_parse_response(struct lua_State *L)
{
	int top = lua_gettop(L);

	if (!top)
		luaL_error(L, "bad arguments");

	size_t len;
	const char *s = lua_tolstring(L, 1, &len);

	struct parse_http_events ev;
	memset(&ev, 0, sizeof(ev));
	ev.on_error               = http_parser_on_error;
	ev.on_header              = http_parser_on_header;
	ev.on_body                = http_parser_on_body;
	ev.on_response_line       = http_parser_on_response_line;

	lua_newtable(L);    /* results */

	lua_newtable(L);    /* headers */
	lua_pushstring(L, "headers");
	lua_pushvalue(L, -2);
	lua_rawset(L, -4);

	httpfast_parse(s, len, &ev, L);

	lua_pop(L, 1);
	return 1;
}

static int
lbox_httpd_parse_request(struct lua_State *L)
{
	int top = lua_gettop(L);

	if (!top)
		luaL_error(L, "bad arguments");

	size_t len;
	const char *s = lua_tolstring(L, 1, &len);

	struct parse_http_events ev;
	memset(&ev, 0, sizeof(ev));
	ev.on_error               = http_parser_on_error;
	ev.on_header              = http_parser_on_header;
	ev.on_body                = http_parser_on_body;
	ev.on_request_line        = http_parser_on_request_line;

	lua_newtable(L);    /* results */

	lua_newtable(L);    /* headers */
	lua_pushstring(L, "headers");
	lua_pushvalue(L, -2);
	lua_rawset(L, -4);

	httpfast_parse(s, len, &ev, L);

	lua_pop(L, 1);
	return 1;
}

static inline int
httpd_on_param(void *uobj, const char *name, size_t name_len,
	       const char *value, size_t value_len)
{
	struct lua_State *L = (struct lua_State *)uobj;

	lua_pushlstring(L, name, name_len);
	lua_pushvalue(L, -1);
	lua_rawget(L, -3);
	if (lua_isnil(L, -1)) {
		lua_pop(L, 1);
		lua_pushlstring(L, value, value_len);
		lua_rawset(L, -3);
		return 0;
	}
	if (lua_istable(L, -1)) {
		lua_pushnumber(L, luaL_getn(L, -1) + 1);
		lua_pushlstring(L, value, value_len);
		lua_rawset(L, -3);
		lua_pop(L, 2);	/* table and name */
		return 0;
	}
	lua_newtable(L);
	lua_pushvalue(L, -2);
	lua_rawseti(L, -2, 1);
	lua_remove(L, -2);

	lua_pushlstring(L, value, value_len);
	lua_rawseti(L, -2, 2);

	lua_rawset(L, -3);
	return 0;
}

static int
lbox_httpd_params(struct lua_State *L)
{
	lua_newtable(L);
	if (!lua_gettop(L))
		return 1;

	const char *s;
	size_t len;
	s = lua_tolstring(L, 1, &len);
	httpfast_parse_params(s, len, httpd_on_param, L);
	return 1;
}

LUA_API int
luaopen_http_lib(lua_State *L)
{
	static const struct luaL_reg reg[] = {
		{"parse_response", lbox_http_parse_response},
		{"template", lbox_httpd_template},
		{"_parse_request", lbox_httpd_parse_request},
		{"params", lbox_httpd_params},
		{NULL, NULL}
	};

	luaL_register(L, "box._lib", reg);
	return 1;
}
