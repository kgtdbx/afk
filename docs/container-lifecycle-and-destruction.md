# What Triggers Container Destruction?

## The Question

```
  Step 17: gh issue close <num>
      ... what happens here? ...
  Container destroyed
```

---

## Answer: Claude's `--print` Mode Exits, Then `--rm` Destroys

There's nothing special between step 17 and container destruction. Here's the
exact sequence:

```
  docker run --rm ... claude --print "$RALPH_PROMPT"
  ----------  ---     ----- -------
     |         |        |      |
     |         |        |      +-- "Respond to this prompt"
     |         |        +-- ONE-SHOT mode: produce one response, then EXIT
     |         +-- "Destroy container when the command finishes"
     +-- "Start a container and run this command"
```

### Step by Step

```
  +--[Container lifecycle]------------------------------------------+
  |                                                                  |
  |  1. docker run creates the container                            |
  |  2. bash -c 'pnpm install; claude --print ...' starts           |
  |  3. pnpm install runs                                           |
  |  4. claude --print starts                                       |
  |                                                                  |
  |  +--[Claude --print is running]------------------------------+  |
  |  |                                                            |  |
  |  |  5. Claude reads the prompt                               |  |
  |  |  6. Claude picks an issue                                 |  |
  |  |  7. Claude reads the issue body (gh issue view)           |  |
  |  |  8. Claude explores code                                  |  |
  |  |  9. Claude implements changes                             |  |
  |  | 10. Claude runs tests                                     |  |
  |  | 11. Claude commits                                        |  |
  |  | 12. Claude closes the issue (gh issue close)              |  |
  |  | 13. Claude outputs its final response text                |  |
  |  | 14. claude --print EXITS (exit code 0)                    |  |
  |  |                                                            |  |
  |  +-------- process ends, returns to bash --------------------+  |
  |                                                                  |
  | 15. bash -c '...' finishes (all commands done)                  |
  | 16. Container's main process has exited                         |
  | 17. --rm flag triggers: Docker destroys the container           |
  |                                                                  |
  +------------------------------------------------------------------+
```

### The Key: `--print` Makes Claude Exit After One Response

```
  Regular claude (interactive):
  ==============================
  $ claude
  > "Fix bug #3"
  Claude: "Done! What's next?"
  > "Now fix #4"              <-- stays alive, waits for input
  Claude: "Done!"
  > /exit                     <-- must explicitly exit

  claude --print (one-shot):
  ===========================
  $ claude --print "Fix bug #3"
  Claude: "Done! Here's what I did..."
  $                            <-- process exits immediately
                                  no waiting, no interaction
```

---

## What Triggers the Container to Die?

```
  It's NOT:
    - A special signal from Claude
    - A Docker timeout
    - The "NO MORE TASKS" string
    - Any explicit "destroy" command

  It IS:
    - The normal process lifecycle:
      1. Process starts (claude --print)
      2. Process does its work
      3. Process exits (claude finishes responding)
      4. Container has no more commands to run
      5. Container exits
      6. --rm removes the container
```

Think of it like a one-use room:

```
  +--[Room]--+
  |           |   1. Person enters room (docker run)
  |  Person   |   2. Person does work (claude --print)
  |  working  |   3. Person finishes and walks out (process exits)
  |           |   4. Room is demolished (--rm)
  +-----------+
```

---

## The Loop: What Checks for NO MORE TASKS?

Important: the NO MORE TASKS check happens OUTSIDE the container, AFTER it's
already destroyed.

```
  +--[afk.sh on your Mac]-------------------------------------------+
  |                                                                   |
  |  for i in 1..5:                                                  |
  |                                                                   |
  |    docker run --rm ... | tee "$tmpfile" | jq ...                 |
  |    ^^^^^^^^^^^^^^^^^^^^                                           |
  |    Container runs, produces output,                               |
  |    output is saved to $tmpfile,                                  |
  |    container is destroyed.                                       |
  |                                                                   |
  |    result=$(jq -r "$final_result" "$tmpfile")                    |
  |    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^                |
  |    AFTER container is dead, read the saved output.               |
  |                                                                   |
  |    if [[ "$result" == *"NO MORE TASKS"* ]]; then                 |
  |      exit 0     # Stop the bash loop                             |
  |    fi                                                             |
  |    # Otherwise, loop back to top --> new container               |
  |                                                                   |
  +-------------------------------------------------------------------+
```

```
  Timeline:

  Iter 1:  Container born --> Claude works --> Container dies --> check output
                                                                      |
                                                               "NO MORE TASKS"?
                                                                   No
                                                                   |
  Iter 2:  Container born --> Claude works --> Container dies --> check output
                                                                      |
                                                               "NO MORE TASKS"?
                                                                   Yes
                                                                   |
                                                                 exit 0
```

---

## Summary

| What | When | Where |
|------|------|-------|
| Container created | Start of each loop iteration | `docker run` in afk.sh |
| Claude starts | After pnpm install | Inside container |
| Claude finishes | After outputting its response | Inside container |
| Container destroyed | When `claude --print` exits | Docker (via `--rm` flag) |
| NO MORE TASKS check | After container is already dead | afk.sh on your Mac |
| Next iteration starts | If NO MORE TASKS not found | afk.sh loop continues |
