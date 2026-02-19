/**
 * Tests for the Include Directive Parser
 */

import { describe, it } from "node:test";
import * as assert from "node:assert";
import * as os from "os";
import * as path from "path";

import {
  normalizePath,
  parseIncludeLine,
  parseIncludeDirectives,
  isIncludeDirective,
  extractIncludePath,
  DEFAULT_MAX_DEPTH,
} from "../includeDirectiveParser.js";

const homeDir = os.homedir();
const basePath = "/project/docs";

describe("includeDirectiveParser", () => {
  describe("normalizePath", () => {
    it("resolves home directory with ~/", () => {
      const result = normalizePath("~/.claude/rules.md", basePath);
      assert.strictEqual(result, path.join(homeDir, ".claude/rules.md"));
    });

    it("resolves home directory alone (~)", () => {
      const result = normalizePath("~", basePath);
      assert.strictEqual(result, homeDir);
    });

    it("handles absolute paths", () => {
      const result = normalizePath("/etc/claude/global.md", basePath);
      assert.strictEqual(result, "/etc/claude/global.md");
    });

    it("resolves relative paths from basePath", () => {
      const result = normalizePath("./local-rules.md", basePath);
      assert.strictEqual(result, "/project/docs/local-rules.md");
    });

    it("resolves relative paths without ./ prefix", () => {
      const result = normalizePath("team/conventions.md", basePath);
      assert.strictEqual(result, "/project/docs/team/conventions.md");
    });

    it("resolves parent directory paths", () => {
      const result = normalizePath("../shared/rules.md", basePath);
      assert.strictEqual(result, "/project/shared/rules.md");
    });

    it("trims whitespace from path", () => {
      const result = normalizePath("  ./local-rules.md  ", basePath);
      assert.strictEqual(result, "/project/docs/local-rules.md");
    });

    it("handles complex relative paths", () => {
      const result = normalizePath("../../other-project/rules.md", basePath);
      assert.strictEqual(result, "/other-project/rules.md");
    });

    it("normalizes paths with redundant separators", () => {
      const result = normalizePath("/etc//claude///rules.md", basePath);
      assert.strictEqual(result, "/etc/claude/rules.md");
    });
  });

  describe("parseIncludeLine", () => {
    it("parses simple @include directive", () => {
      const result = parseIncludeLine(
        "@include ./local-rules.md",
        1,
        basePath
      );
      assert.notStrictEqual(result, null);
      assert.strictEqual(result?.rawPath, "./local-rules.md");
      assert.strictEqual(result?.resolvedPath, "/project/docs/local-rules.md");
      assert.strictEqual(result?.lineNumber, 1);
    });

    it("parses @include with leading whitespace", () => {
      const result = parseIncludeLine(
        "  @include ~/.claude/rules.md",
        5,
        basePath
      );
      assert.notStrictEqual(result, null);
      assert.strictEqual(result?.rawPath, "~/.claude/rules.md");
      assert.strictEqual(
        result?.resolvedPath,
        path.join(homeDir, ".claude/rules.md")
      );
    });

    it("parses @include with tabs", () => {
      const result = parseIncludeLine(
        "\t@include /absolute/path.md",
        10,
        basePath
      );
      assert.notStrictEqual(result, null);
      assert.strictEqual(result?.rawPath, "/absolute/path.md");
      assert.strictEqual(result?.resolvedPath, "/absolute/path.md");
    });

    it("returns null for non-directive lines", () => {
      assert.strictEqual(
        parseIncludeLine("# Just a comment", 1, basePath),
        null
      );
      assert.strictEqual(parseIncludeLine("Some text", 1, basePath), null);
      assert.strictEqual(parseIncludeLine("", 1, basePath), null);
    });

    it("returns null for malformed directives", () => {
      // No path provided
      assert.strictEqual(parseIncludeLine("@include", 1, basePath), null);
      assert.strictEqual(parseIncludeLine("@include ", 1, basePath), null);
      assert.strictEqual(parseIncludeLine("@include   ", 1, basePath), null);
    });

    it("does not match @include in middle of line", () => {
      assert.strictEqual(
        parseIncludeLine("Some text @include ./file.md", 1, basePath),
        null
      );
    });

    it("handles paths with spaces", () => {
      const result = parseIncludeLine(
        "@include ./my file with spaces.md",
        1,
        basePath
      );
      assert.notStrictEqual(result, null);
      assert.strictEqual(result?.rawPath, "./my file with spaces.md");
    });

    it("preserves original line", () => {
      const originalLine = "  @include ~/.claude/rules.md";
      const result = parseIncludeLine(originalLine, 1, basePath);
      assert.strictEqual(result?.originalLine, originalLine);
    });
  });

  describe("parseIncludeDirectives", () => {
    it("parses multiple directives from content", () => {
      const content = `# Project Rules

@include ~/.claude/languages/go.md
@include ./team-conventions.md

Some other content

@include /shared/global-rules.md
`;
      const result = parseIncludeDirectives(content, basePath);

      assert.strictEqual(result.directives.length, 3);
      assert.strictEqual(result.errors.length, 0);

      assert.strictEqual(
        result.directives[0].rawPath,
        "~/.claude/languages/go.md"
      );
      assert.strictEqual(result.directives[0].lineNumber, 3);

      assert.strictEqual(result.directives[1].rawPath, "./team-conventions.md");
      assert.strictEqual(result.directives[1].lineNumber, 4);

      assert.strictEqual(
        result.directives[2].rawPath,
        "/shared/global-rules.md"
      );
      assert.strictEqual(result.directives[2].lineNumber, 8);
    });

    it("returns empty array for content without directives", () => {
      const content = `# Just some markdown

No include directives here.

Just regular content.
`;
      const result = parseIncludeDirectives(content, basePath);

      assert.strictEqual(result.directives.length, 0);
      assert.strictEqual(result.errors.length, 0);
    });

    it("preserves original content", () => {
      const content = "@include ./rules.md\nSome content";
      const result = parseIncludeDirectives(content, basePath);

      assert.strictEqual(result.originalContent, content);
    });

    it("reports errors for invalid directives", () => {
      const content = `@include ./valid.md
@include
@include
@include ./another-valid.md
`;
      const result = parseIncludeDirectives(content, basePath);

      assert.strictEqual(result.directives.length, 2);
      assert.strictEqual(result.errors.length, 2);

      assert.strictEqual(result.errors[0].lineNumber, 2);
      assert.ok(result.errors[0].message.includes("path cannot be empty"));

      assert.strictEqual(result.errors[1].lineNumber, 3);
    });

    it("handles empty content", () => {
      const result = parseIncludeDirectives("", basePath);

      assert.strictEqual(result.directives.length, 0);
      assert.strictEqual(result.errors.length, 0);
      assert.strictEqual(result.originalContent, "");
    });

    it("handles content with only whitespace", () => {
      const result = parseIncludeDirectives("   \n\n  \t\n", basePath);

      assert.strictEqual(result.directives.length, 0);
      assert.strictEqual(result.errors.length, 0);
    });

    it("correctly numbers lines", () => {
      const content = `Line 1
Line 2
@include ./first.md
Line 4
Line 5
@include ./second.md`;

      const result = parseIncludeDirectives(content, basePath);

      assert.strictEqual(result.directives[0].lineNumber, 3);
      assert.strictEqual(result.directives[1].lineNumber, 6);
    });
  });

  describe("isIncludeDirective", () => {
    it("returns true for valid @include lines", () => {
      assert.strictEqual(isIncludeDirective("@include ./file.md"), true);
      assert.strictEqual(
        isIncludeDirective("  @include ~/.claude/rules.md"),
        true
      );
      assert.strictEqual(
        isIncludeDirective("\t@include /absolute/path.md"),
        true
      );
    });

    it("returns false for non-directive lines", () => {
      assert.strictEqual(isIncludeDirective("# Comment"), false);
      assert.strictEqual(isIncludeDirective("Some text"), false);
      assert.strictEqual(isIncludeDirective(""), false);
      assert.strictEqual(
        isIncludeDirective("Text @include ./file.md"),
        false
      );
    });

    it("returns false for @include with empty path", () => {
      assert.strictEqual(isIncludeDirective("@include "), false);
    });
  });

  describe("extractIncludePath", () => {
    it("extracts path from valid directive", () => {
      assert.strictEqual(extractIncludePath("@include ./file.md"), "./file.md");
      assert.strictEqual(
        extractIncludePath("@include ~/.claude/rules.md"),
        "~/.claude/rules.md"
      );
      assert.strictEqual(
        extractIncludePath("  @include /absolute/path.md"),
        "/absolute/path.md"
      );
    });

    it("returns null for non-directive lines", () => {
      assert.strictEqual(extractIncludePath("# Comment"), null);
      assert.strictEqual(extractIncludePath("Some text"), null);
      assert.strictEqual(extractIncludePath(""), null);
    });

    it("returns null for empty path", () => {
      assert.strictEqual(extractIncludePath("@include "), null);
      assert.strictEqual(extractIncludePath("@include   "), null);
    });

    it("trims extracted path", () => {
      assert.strictEqual(
        extractIncludePath("@include   ./file.md  "),
        "./file.md"
      );
    });
  });

  describe("edge cases", () => {
    it("handles @include directive with various file extensions", () => {
      const extensions = [".md", ".txt", ".yaml", ".json", ".claude"];
      for (const ext of extensions) {
        const result = parseIncludeLine(
          `@include ./config${ext}`,
          1,
          basePath
        );
        assert.notStrictEqual(result, null);
        assert.strictEqual(result?.rawPath, `./config${ext}`);
      }
    });

    it("handles deeply nested relative paths", () => {
      const result = normalizePath(
        "./a/b/c/d/e/f/deeply-nested.md",
        basePath
      );
      assert.strictEqual(
        result,
        "/project/docs/a/b/c/d/e/f/deeply-nested.md"
      );
    });

    it("handles Windows-style paths in cross-platform way", () => {
      // The path module should normalize these appropriately
      const result = normalizePath("./folder\\file.md", basePath);
      // On Unix, backslash is a valid filename character
      // On Windows, it would be normalized to forward slash
      assert.ok(result);
    });

    it("handles unicode characters in paths", () => {
      const result = parseIncludeLine(
        "@include ./日本語/ファイル.md",
        1,
        basePath
      );
      assert.notStrictEqual(result, null);
      assert.strictEqual(result?.rawPath, "./日本語/ファイル.md");
    });

    it("handles emoji in paths", () => {
      const result = parseIncludeLine(
        "@include ./docs/📚-notes.md",
        1,
        basePath
      );
      assert.notStrictEqual(result, null);
      assert.strictEqual(result?.rawPath, "./docs/📚-notes.md");
    });

    it("does not match case-insensitive @INCLUDE", () => {
      // @include is case-sensitive
      assert.strictEqual(isIncludeDirective("@INCLUDE ./file.md"), false);
      assert.strictEqual(isIncludeDirective("@Include ./file.md"), false);
    });
  });

  describe("backward compatibility", () => {
    it("@include directive does not interfere with @path/to/file.md syntax", () => {
      // The @include syntax should be distinct from the existing @path syntax
      // @path/to/file.md starts directly with @ followed by the path
      // @include has a space between @include and the path

      // This should NOT match @include pattern (no 'include' keyword)
      assert.strictEqual(isIncludeDirective("@./file.md"), false);
      assert.strictEqual(isIncludeDirective("@~/config.md"), false);
      assert.strictEqual(isIncludeDirective("@/absolute/path.md"), false);

      // These SHOULD match @include pattern
      assert.strictEqual(isIncludeDirective("@include ./file.md"), true);
      assert.strictEqual(isIncludeDirective("@include ~/config.md"), true);
      assert.strictEqual(
        isIncludeDirective("@include /absolute/path.md"),
        true
      );
    });
  });

  describe("DEFAULT_MAX_DEPTH", () => {
    it("has a sensible default value", () => {
      assert.strictEqual(DEFAULT_MAX_DEPTH, 10);
      assert.ok(DEFAULT_MAX_DEPTH > 0);
    });
  });
});
