/**
 * Include Directive Parser for CLAUDE.md files
 *
 * Parses `@include <path>` directives and resolves file paths.
 * This is an alternative/addition to the existing `@path/to/file.md` syntax.
 *
 * Supported path formats:
 * - Absolute: `@include /home/user/.claude/rules.md`
 * - Home-relative: `@include ~/.claude/languages/go.md`
 * - Relative: `@include ./local-rules.md` (relative to including file)
 */

import * as path from "path";
import * as os from "os";

/**
 * Represents a parsed include directive
 */
export interface IncludeDirective {
  /** The original line from the source file */
  originalLine: string;
  /** The line number in the source file (1-indexed) */
  lineNumber: number;
  /** The raw path as specified in the directive */
  rawPath: string;
  /** The fully resolved absolute path */
  resolvedPath: string;
}

/**
 * Result of parsing a file for include directives
 */
export interface ParseResult {
  /** The original content with directives intact */
  originalContent: string;
  /** List of parsed include directives */
  directives: IncludeDirective[];
  /** Any parsing errors encountered */
  errors: ParseError[];
}

/**
 * Represents a parsing error
 */
export interface ParseError {
  /** The line number where the error occurred (1-indexed) */
  lineNumber: number;
  /** The original line content */
  line: string;
  /** Description of the error */
  message: string;
}

/**
 * Regular expression to match @include directives with a path
 * - Matches at the start of a line (with optional leading whitespace)
 * - Captures the path after @include
 * - Path can contain spaces if not at end of line
 */
const INCLUDE_DIRECTIVE_REGEX = /^\s*@include\s+(.+)$/;

/**
 * Regular expression to match incomplete @include directives (without a path)
 * - Matches at the start of a line (with optional leading whitespace)
 * - Matches @include followed by optional whitespace but no path
 */
const INCOMPLETE_INCLUDE_REGEX = /^\s*@include\s*$/;

/**
 * Normalizes a path by resolving home directory (~) and making it absolute
 *
 * @param inputPath - The path to normalize
 * @param basePath - The base path for resolving relative paths (directory of including file)
 * @returns The normalized absolute path
 */
export function normalizePath(inputPath: string, basePath: string): string {
  const trimmedPath = inputPath.trim();

  // Handle home directory (~) expansion
  if (trimmedPath.startsWith("~/") || trimmedPath === "~") {
    const homeDir = os.homedir();
    if (trimmedPath === "~") {
      return homeDir;
    }
    return path.join(homeDir, trimmedPath.slice(2));
  }

  // Handle absolute paths
  if (path.isAbsolute(trimmedPath)) {
    return path.normalize(trimmedPath);
  }

  // Handle relative paths (relative to the including file's directory)
  return path.resolve(basePath, trimmedPath);
}

/**
 * Parses a single line for an @include directive
 *
 * @param line - The line to parse
 * @param lineNumber - The line number (1-indexed)
 * @param basePath - The base path for resolving relative paths
 * @returns The parsed directive or null if line is not an @include directive
 */
export function parseIncludeLine(
  line: string,
  lineNumber: number,
  basePath: string
): IncludeDirective | null {
  const match = line.match(INCLUDE_DIRECTIVE_REGEX);
  if (!match) {
    return null;
  }

  const rawPath = match[1].trim();

  // Validate that a path was actually provided
  if (!rawPath) {
    return null;
  }

  const resolvedPath = normalizePath(rawPath, basePath);

  return {
    originalLine: line,
    lineNumber,
    rawPath,
    resolvedPath,
  };
}

/**
 * Parses content for all @include directives
 *
 * @param content - The file content to parse
 * @param basePath - The base path for resolving relative paths (directory of the file)
 * @returns ParseResult containing all directives and any errors
 */
export function parseIncludeDirectives(
  content: string,
  basePath: string
): ParseResult {
  const lines = content.split("\n");
  const directives: IncludeDirective[] = [];
  const errors: ParseError[] = [];

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const lineNumber = i + 1;

    // Check if line matches a complete @include directive
    if (INCLUDE_DIRECTIVE_REGEX.test(line)) {
      const directive = parseIncludeLine(line, lineNumber, basePath);

      if (directive) {
        directives.push(directive);
      } else {
        // Line matched the pattern but parsing failed (e.g., empty path)
        errors.push({
          lineNumber,
          line,
          message: "Invalid @include directive: path cannot be empty",
        });
      }
      continue;
    }

    // Check if line is an incomplete @include directive (missing path)
    if (INCOMPLETE_INCLUDE_REGEX.test(line)) {
      errors.push({
        lineNumber,
        line,
        message: "Invalid @include directive: path cannot be empty",
      });
    }
  }

  return {
    originalContent: content,
    directives,
    errors,
  };
}

/**
 * Checks if a line contains an @include directive
 *
 * @param line - The line to check
 * @returns true if the line is an @include directive
 */
export function isIncludeDirective(line: string): boolean {
  return INCLUDE_DIRECTIVE_REGEX.test(line);
}

/**
 * Extracts the path from an @include directive line
 *
 * @param line - The line containing the directive
 * @returns The extracted path or null if not a valid directive
 */
export function extractIncludePath(line: string): string | null {
  const match = line.match(INCLUDE_DIRECTIVE_REGEX);
  if (!match) {
    return null;
  }
  const rawPath = match[1].trim();
  return rawPath || null;
}

/**
 * Options for content processing
 */
export interface ProcessOptions {
  /** Function to read file content (for dependency injection in tests) */
  readFile?: (path: string) => Promise<string>;
  /** Set of already-included paths to detect circular includes */
  includedPaths?: Set<string>;
  /** Maximum include depth to prevent excessive nesting */
  maxDepth?: number;
  /** Current depth (used internally) */
  currentDepth?: number;
}

/**
 * Result of processing content with includes
 */
export interface ProcessResult {
  /** The content with all includes resolved and merged */
  content: string;
  /** List of all included file paths */
  includedPaths: string[];
  /** Any errors encountered during processing */
  errors: ProcessError[];
}

/**
 * Represents a processing error (file not found, circular include, etc.)
 */
export interface ProcessError {
  /** The file path where the error occurred */
  filePath: string;
  /** The line number (if applicable) */
  lineNumber?: number;
  /** Description of the error */
  message: string;
  /** Error type for categorization */
  type: "file_not_found" | "circular_include" | "max_depth" | "read_error" | "parse_error";
}

/**
 * Default maximum include depth
 */
export const DEFAULT_MAX_DEPTH = 10;
