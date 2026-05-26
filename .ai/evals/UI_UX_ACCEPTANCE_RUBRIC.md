# UI/UX Acceptance Rubric

## Score Ranges

| Score | Rating | Description |
|-------|--------|-------------|
| 90-100 | Excellent | Pixel-perfect, accessible, responsive, performant |
| 75-89 | Good | Minor visual or UX issues |
| 60-74 | Adequate | Functional but rough edges |
| < 60 | Needs Work | Significant UX or visual problems |

## Dimensions

### Visual Quality (20 points)
- Matches design spec (if provided)
- Consistent spacing and typography
- Proper color usage
- No visual glitches

### Responsiveness (20 points)
- Works on mobile (320px+)
- Works on tablet (768px+)
- Works on desktop (1024px+)
- No horizontal scroll on mobile

### Accessibility (20 points)
- Keyboard navigable
- Focus indicators visible
- ARIA labels where needed
- Color contrast >= 4.5:1
- Screen reader compatible

### State Handling (20 points)
- Loading state shown
- Empty state handled
- Error state with helpful message
- Success state confirmed
- Edge cases (long text, no data, etc.)

### Performance (20 points)
- No layout shift (CLS < 0.1)
- Interactive within 2 seconds
- Images optimized
- No render-blocking resources

## Automatic Checks
- Lighthouse accessibility score >= 90
- No console errors
- No 404s on resources

## What Blocks 100/100
- Accessibility violation (keyboard trap, missing labels)
- Layout break at any supported breakpoint
- Missing error/empty state
- Console error
- CLS > 0.25
