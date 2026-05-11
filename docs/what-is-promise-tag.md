# What is `<promise>NO MORE TASKS</promise>`?

## It's NOT a Docker thing. It's NOT a JavaScript Promise.

It's just a **magic string** -- a unique marker that the bash script (or
Sandcastle) searches for in Claude's output.

---

## How It Works

```
  Claude's output is just text. Lots of text.

  The script needs to know: "Did Claude finish all the work?"

  Solution: Tell Claude "when you're done, say this exact phrase."
  Then search the output for that phrase.
```

### In `prompt.md` (what Claude reads):

```markdown
If all tasks are complete, output <promise>NO MORE TASKS</promise>.
```

### In `ralph/afk.sh` (what checks for it):

```bash
if [[ "$result" == *"<promise>NO MORE TASKS</promise>"* ]]; then
    echo "Ralph complete after $i iterations."
    exit 0
fi
```

### In `sandcastle/main.ts` (what checks for it):

```typescript
completionSignal: "<promise>NO MORE TASKS</promise>",
```

---

## Why `<promise>` tags?

The angle brackets make the string **extremely unlikely to appear by accident**.

```
  Bad signal:  "NO MORE TASKS"
  Problem:     Claude might say "there are no more tasks to discuss"
               and trigger a false positive.

  Good signal: "<promise>NO MORE TASKS</promise>"
  Why:         Claude would never accidentally output XML-like tags
               wrapping that exact phrase unless it intended to.
```

It's the same idea as using a UUID or a special delimiter. The `<promise>`
tag name is just a convention -- it could have been `<done>`, `<stop>`,
or `<banana>FINISHED</banana>`. The word "promise" has no technical
meaning here.

---

## Flow

```
  Iteration 1:
    Claude: "I implemented issue #3. Committed and closed."
    Script checks: contains "<promise>NO MORE TASKS</promise>"?
    --> NO --> continue

  Iteration 2:
    Claude: "I implemented issue #7. Committed and closed."
    Script checks: contains "<promise>NO MORE TASKS</promise>"?
    --> NO --> continue

  Iteration 3:
    Claude: "All issues are complete. <promise>NO MORE TASKS</promise>"
    Script checks: contains "<promise>NO MORE TASKS</promise>"?
    --> YES --> exit the loop, we're done
```

---

## Summary

| Question | Answer |
|----------|--------|
| Is it a Docker thing? | No |
| Is it a JavaScript Promise? | No |
| Is it a programming concept? | No |
| What is it? | A magic string / sentinel value |
| Who outputs it? | Claude (the AI), when all issues are done |
| Who reads it? | The bash script or Sandcastle library |
| Why angle brackets? | To avoid accidental matches |
