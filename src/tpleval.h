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
#ifndef TPL_EVAL_H_INCLUDED
#define TPL_EVAL_H_INCLUDED

#include <stdlib.h>
#include <stdio.h>

enum {
	TPE_TEXT,
	TPE_LINECODE,
	TPE_MULTILINE_CODE
};

static inline void
tpe_parse(const char *p, size_t len,
	void(*term)(int type, const char *str, size_t len, void *data),
	void *data)
{
	int bl = 1;
	size_t i, be;
	int type = TPE_TEXT;

	for (be = i = 0; i < len; i++) {
		if (type == TPE_TEXT) {
			switch(p[i]) {
				case ' ':
				case '\t':
					break;
				case '%':
					if (bl) {
						if (be < i)
							term(type,
								p + be,
								i - be,
								data);

						be = i + 1;
						bl = 0;

						type = TPE_LINECODE;
						break;
					}

					if (i == 0 || p[i - 1] != '<')
						break;

					if (be < i - 1)
						term(type,
							p + be,
							i - be - 1,
							data);
					be = i + 1;
					bl = 0;

					type = TPE_MULTILINE_CODE;
					break;

				case '\n':
					if (be <= i)
						term(type,
							p + be,
							i - be + 1,
							data);
					be = i + 1;
					bl = 1;
					break;
				default:
					bl = 0;
					break;
			}
			continue;
		}

		if (type == TPE_LINECODE) {
			switch(p[i]) {
				case '\n':
					if (be < i)
						term(type,
							p + be, i - be, data);
					be = i;
					type = TPE_TEXT;
					bl = 1;
					break;
				default:
					break;
			}
			continue;
		}

		if (type == TPE_MULTILINE_CODE) {
			switch(p[i]) {
				case '%':
					if (i == len - 1 || p[i + 1] != '>')
						continue;
					if (be < i)
						term(type,
							p + be, i - be, data);
					be = i + 2;
					i++;
					bl = 0;
					type = TPE_TEXT;
					break;
				default:
					break;
			}
			continue;
		}

		abort();
	}

	if (len == 0 || be >= len)
		return;

	switch(type) {
		/* unclosed multiline tag as text */
		case TPE_MULTILINE_CODE:
			if (be >= 2)
				be -= 2;
			type = TPE_TEXT;

		case TPE_LINECODE:
		case TPE_TEXT:
			term(type, p + be, len - be, data);
			break;
		default:
			break;
	}
}


#endif /* TPL_EVAL_H_INCLUDED */
