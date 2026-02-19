/**
 * Claude Code - AI-powered coding assistant
 *
 * This module exports utilities for parsing and processing CLAUDE.md files.
 */

// Export include directive parser utilities
export {
  normalizePath,
  parseIncludeLine,
  parseIncludeDirectives,
  isIncludeDirective,
  extractIncludePath,
  DEFAULT_MAX_DEPTH,
  type IncludeDirective,
  type ParseResult,
  type ParseError,
  type ProcessOptions,
  type ProcessResult,
  type ProcessError,
} from "./utils/includeDirectiveParser";
