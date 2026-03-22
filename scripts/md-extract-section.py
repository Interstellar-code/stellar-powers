#!/usr/bin/env python3
"""Read or replace a section in a Markdown file by heading.

Zero dependencies — uses only Python stdlib.

Read mode (default):
  python3 md-extract-section.py FILE "Task 3"
  python3 md-extract-section.py FILE "Task 3" "Task 4" "Task 5"
  python3 md-extract-section.py FILE --pattern "Task [0-9]+"
  python3 md-extract-section.py FILE --overview

Write mode (--write):
  python3 md-extract-section.py FILE --write "Task 3" <<< "new content"
  echo "new content" | python3 md-extract-section.py FILE --write --pattern "Task 3:"

  Replaces the matched section's body (preserving the heading) with stdin content.
  Writes the result back to the file. Prints the updated section to stdout.

Matching:
  - Case-insensitive substring match on heading text
  - Extracts from the matched heading down to the next heading of same or higher level
  - --pattern uses regex matching instead of substring

Output:
  - Read: Extracted section(s) printed to stdout, exit 0 if matched
  - Write: Updated file in-place, prints updated section, exit 0 if matched
  - Exit 1 if no sections matched
"""
import re
import sys


def parse_headings(lines):
    """Parse markdown into (level, title, start_line, end_line) tuples."""
    sections = []
    for i, line in enumerate(lines):
        m = re.match(r'^(#{1,6})\s+(.+)$', line)
        if m:
            level = len(m.group(1))
            title = m.group(2).strip()
            sections.append((level, title, i))

    # Compute end lines
    result = []
    for idx, (level, title, start) in enumerate(sections):
        end = len(lines)
        for next_level, _, next_start in sections[idx + 1:]:
            if next_level <= level:
                end = next_start
                break
        result.append((level, title, start, end))
    return result


def extract(lines, queries, use_regex=False):
    """Extract sections matching any query."""
    sections = parse_headings(lines)
    extracted = []

    for level, title, start, end in sections:
        title_lower = title.lower()
        matched = False
        for q in queries:
            if use_regex:
                if re.search(q, title, re.IGNORECASE):
                    matched = True
                    break
            else:
                if q.lower() in title_lower:
                    matched = True
                    break
        if matched:
            extracted.append('\n'.join(lines[start:end]).rstrip())

    return extracted


def extract_overview(lines):
    """Extract everything before the first ## or deeper heading."""
    for i, line in enumerate(lines):
        if re.match(r'^#{2,6}\s+', line) and i > 0:
            return '\n'.join(lines[:i]).rstrip()
    return '\n'.join(lines).rstrip()


def replace_section(lines, query, new_content, use_regex=False):
    """Replace the body of a matched section, preserving the heading."""
    sections = parse_headings(lines)

    for level, title, start, end in sections:
        matched = False
        if use_regex:
            if re.search(query, title, re.IGNORECASE):
                matched = True
        else:
            if query.lower() in title.lower():
                matched = True

        if matched:
            heading_line = lines[start]
            new_lines = lines[:start] + [heading_line, ''] + new_content.splitlines() + [''] + lines[end:]
            updated_section = heading_line + '\n\n' + new_content
            return new_lines, updated_section

    return None, None


def main():
    if len(sys.argv) < 3:
        print(__doc__, file=sys.stderr)
        sys.exit(2)

    filepath = sys.argv[1]
    use_regex = '--pattern' in sys.argv
    overview = '--overview' in sys.argv
    write_mode = '--write' in sys.argv

    try:
        with open(filepath) as f:
            lines = f.read().splitlines()
    except FileNotFoundError:
        print(f"ERROR: File not found: {filepath}", file=sys.stderr)
        sys.exit(1)

    if overview:
        result = extract_overview(lines)
        if result:
            print(result)
            sys.exit(0)
        sys.exit(1)

    queries = [a for a in sys.argv[2:] if a not in ('--pattern', '--write', '--overview')]
    if not queries:
        print("ERROR: No section names provided", file=sys.stderr)
        sys.exit(2)

    if write_mode:
        if len(queries) != 1:
            print("ERROR: --write requires exactly one section name", file=sys.stderr)
            sys.exit(2)
        new_content = sys.stdin.read().rstrip()
        new_lines, updated = replace_section(lines, queries[0], new_content, use_regex=use_regex)
        if new_lines is not None:
            with open(filepath, 'w') as f:
                f.write('\n'.join(new_lines))
            print(updated)
            sys.exit(0)
        else:
            print(f"No section matched: {queries[0]}", file=sys.stderr)
            sys.exit(1)

    results = extract(lines, queries, use_regex=use_regex)

    if results:
        print('\n\n'.join(results))
        sys.exit(0)
    else:
        print(f"No sections matched: {queries}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
