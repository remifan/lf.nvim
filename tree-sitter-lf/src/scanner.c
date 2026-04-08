/**
 * External scanner for tree-sitter-lf
 *
 * Handles code blocks ({= ... =}) which can contain arbitrary target language code.
 * The content between {= and =} should be captured as a single token without
 * trying to parse it as LF syntax.
 */

#include "tree_sitter/parser.h"
#include <string.h>

enum TokenType {
  CODE_BODY,
};

void *tree_sitter_lf_external_scanner_create(void) { return NULL; }

void tree_sitter_lf_external_scanner_destroy(void *payload) {}

unsigned tree_sitter_lf_external_scanner_serialize(void *payload, char *buffer) {
  return 0;
}

void tree_sitter_lf_external_scanner_deserialize(void *payload, const char *buffer,
                                                  unsigned length) {}

static void advance(TSLexer *lexer) { lexer->advance(lexer, false); }

static void skip(TSLexer *lexer) { lexer->advance(lexer, true); }

/**
 * Scan for code body content between {= and =}
 *
 * This scanner is called after {= has been matched.
 * It consumes everything until it finds =} (accounting for potential
 * operator combinations like +=} or -=} which are valid in target languages).
 */
bool tree_sitter_lf_external_scanner_scan(void *payload, TSLexer *lexer,
                                           const bool *valid_symbols) {
  if (!valid_symbols[CODE_BODY]) {
    return false;
  }

  // Track if we've consumed any characters
  bool has_content = false;

  while (true) {
    // Check for end of input
    if (lexer->eof(lexer)) {
      // Unterminated code block - return what we have
      if (has_content) {
        lexer->result_symbol = CODE_BODY;
        return true;
      }
      return false;
    }

    // Look for =} which ends the code block
    // Also handle operator= patterns like +=}, -=}, *=}, /=}, %=}, &=}, ^=}, |=}, <<=}, >>=}
    if (lexer->lookahead == '=') {
      lexer->mark_end(lexer);
      advance(lexer);

      if (lexer->lookahead == '}') {
        // Found =} - this ends the code block
        // Don't consume the =} - let the grammar handle it
        lexer->result_symbol = CODE_BODY;
        return true;
      }

      // The = was part of the code content
      has_content = true;
      continue;
    }

    // Also check for compound operators ending with =}
    // These are: +=} -=} *=} /=} %=} &=} ^=} |=} <<=} >>=}
    if (lexer->lookahead == '+' || lexer->lookahead == '-' ||
        lexer->lookahead == '*' || lexer->lookahead == '/' ||
        lexer->lookahead == '%' || lexer->lookahead == '&' ||
        lexer->lookahead == '^' || lexer->lookahead == '|') {
      lexer->mark_end(lexer);
      int32_t op = lexer->lookahead;
      advance(lexer);

      if (lexer->lookahead == '=') {
        advance(lexer);
        if (lexer->lookahead == '}') {
          // Found <op>=} - this ends the code block with an operator assignment
          // Don't consume the <op>=} - let the grammar handle it
          // Actually, we need to back up to just before the operator
          lexer->result_symbol = CODE_BODY;
          return true;
        }
      }

      // Not a terminator, continue consuming
      has_content = true;
      continue;
    }

    // Handle << and >> compound operators (for <<=} and >>=})
    if (lexer->lookahead == '<' || lexer->lookahead == '>') {
      lexer->mark_end(lexer);
      int32_t bracket = lexer->lookahead;
      advance(lexer);

      if (lexer->lookahead == bracket) {
        advance(lexer);
        if (lexer->lookahead == '=') {
          advance(lexer);
          if (lexer->lookahead == '}') {
            // Found <<=} or >>=}
            lexer->result_symbol = CODE_BODY;
            return true;
          }
        }
      }

      // Not a terminator, continue consuming
      has_content = true;
      continue;
    }

    // Consume any other character as part of the code body
    has_content = true;
    advance(lexer);
  }
}
