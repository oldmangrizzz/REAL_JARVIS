# Skill: pdf-optimizer

Apply print CSS to an HTML proposal so it exports cleanly via browser Print-to-PDF.

## Inputs

- `html_path`: path to the web HTML proposal
- `pdf_margin` (optional, default `0.5in`): minimum print margin

## Output

An updated HTML file (or a second `-print.html` file) that, when opened in a browser and exported via Print → Save as PDF, produces a clean multi-page PDF with no orphaned headers, no split pricing blocks, and no lost background colors.

## The Four Print CSS Fixes

### 1. Force print margins

```css
@media print {
  @page { margin: 0.5in; }
  body { margin: 0; }
}
```

### 2. Force background colors to render

Chrome, Safari, and Firefox skip background colors in print by default. Every dark block (hero section, CTA card, dark footer) needs:

```css
@media print {
  .dark-section {
    background-color: #0D9488 !important;
    color: #ffffff !important;
    -webkit-print-color-adjust: exact;
    print-color-adjust: exact;
  }
}
```

### 3. Keep content blocks whole

```css
@media print {
  h1, h2, h3 { page-break-after: avoid; }
  .pricing-tier,
  .signature-block,
  .cta,
  .why-me,
  table, figure {
    page-break-inside: avoid;
  }
  .new-section {
    page-break-before: always;
  }
}
```

### 4. Hide screen-only chrome

```css
@media print {
  .nav, .hover-cta, .tooltip, .interactive-only {
    display: none !important;
  }
  a[href]:after { content: ""; } /* suppress link URLs in print */
}
```

## Process

1. **Read** the HTML file.
2. **Check** for an existing `<style>` block or linked stylesheet. If there is none, add one.
3. **Inject** the four print CSS blocks above, customizing the dark-section selectors to match the actual class names in the HTML.
4. **Verify** — ensure `<meta name="viewport">` is present and there is no `display: flex` on elements that wrap pricing tiers (flex containers can force content off-page).
5. **Write** the updated HTML back to disk as `<original>-print.html`.
6. **Report** — list what was changed and flag any remaining risks (e.g. "pricing grid uses CSS grid; test at Letter and A4 before sending").

## Safety

- Do not fetch remote stylesheets or fonts during optimization. Inline what is needed. Remote dependencies break offline and leak client proposal URLs to third-party CDNs.
- Do not strip existing author styling — only add print rules on top.
