# Series CSV format (FEATURE-15)

A series renders one thumbnail per row from a single, locked source design.
Rows can be typed in the Series sheet or imported from a CSV file.

## Columns

| Header    | Required | Meaning |
|-----------|----------|---------|
| `title`   | yes      | Replaces the design's headline, or fills `{title}` wherever the design's text uses it. Up to 100 characters. |
| `episode` | no       | Fills `{episode}` in the headline, text layers and badge/callout labels. |
| `image`   | no       | An image file name. After importing, use **Add Image Files…**; images are matched to rows by file name, ignoring case. A row whose image has not been added yet cannot render. |
| `name`    | no       | Output file name (sanitised). Default: `<series>-<episode>` or `<series>-<row number>`. Duplicate names are an error on the later row only. |

Header names ignore letter case and surrounding spaces; column order is free.
Other columns are ignored and listed once after the import.

## Encoding and quoting

- UTF-8, with or without a byte-order mark. Export from spreadsheets as "CSV UTF-8".
- Comma separated. LF, CRLF or CR line endings. Blank lines are skipped.
- RFC 4180 quoting: wrap a value in double quotes when it contains a comma, a
  quote or a line break; write a quote inside quotes as `""`.
- Up to 100 rows per series (the whole file is rejected above that).

## Errors

File-level (nothing is imported): not UTF-8, empty, no `title` column,
a duplicated header, more than 100 rows.

Record-level (only that line is affected): a line with the wrong number of
fields, a quote that is never closed, or text after a closing quote. The
line is kept as a row showing `CSV line N: ...` so it can be fixed in place;
parsing resumes on the next line, so one bad line never hides the others.

## Source and slots

The source is either the design that was open when the series was created or
a personal template (FEATURE-05). Rows are rendered through the template's
slot policies: "Use project's" slots take the row's title / image, "Keep
template's" slots ignore them (the row shows a warning), "Leave empty" slots
stay empty. Editing the design later never changes a series; use
**Use Current Design Instead…** to re-capture explicitly.

Rendering uses the Export All recipes (sizes, format, quality, file-size
budget) and destinations (a Files folder or Photos).

## Sample

```csv
title,episode,image,name
How I Edit Thumbnails,1,episode-01.jpg,
"Lighting, Explained",2,episode-02.jpg,
"The ""Perfect"" Setup",3,,setup-special
```
