# TDD Protocol for Engineering Tasks

## The Iron Law

**No production code without a failing test first.**

If you wrote code before writing a test for it, DELETE the code and start with the test. This is not optional. This is not flexible. This is the rule.

## RED-GREEN-REFACTOR Cycle

### RED: Write a Failing Test

1. Write a test that describes the behavior you want
2. Run it. It MUST fail.
3. Verify it fails for the RIGHT reason (not a syntax error or import issue)
4. If it passes without new code: either the behavior already exists (great, move on) or the test is wrong (fix it)

### GREEN: Make It Pass

1. Write the MINIMUM code to make the test pass
2. Do not write "clean" code yet — just make it work
3. Run all tests. They must ALL pass (new + existing).
4. If existing tests break, you introduced a regression. Fix it before moving on.

### REFACTOR: Clean Up

1. Now improve the code: extract, rename, simplify
2. Run tests after EACH change. Stay green the entire time.
3. If a refactor breaks a test: undo the refactor, don't "fix" the test to match

## What Counts as a Test

- Unit test with an assertion: YES
- Running the code and eyeballing the output: NO
- A comment that says "// tested manually": NO
- Logging + visual inspection: NO

## When TDD Applies

- **Engineering tasks**: Always. Every `eng-*` task follows TDD.
- **Architecture tasks**: No. These produce design docs, not code.
- **UI/UX tasks**: No. These produce specs and wireframes.
- **QA tasks**: QA tasks ARE tests. They write tests for existing code — the RED phase is verifying the test catches real behavior, not writing more tests for the tests.

## Red Flags

| What You're Doing | Why It's Wrong |
|-------------------|---------------|
| "Let me implement the function first, then test it" | You'll write tests that match the code, not the spec |
| "This is too simple to test" | Simple things break too. Write the test. |
| "I'll test the whole module at once" | Test one behavior at a time. Small red-green cycles. |
| "The test framework isn't set up yet" | Set it up. That's part of the task. |
| "I'll refactor later" | Refactor NOW while tests are green and context is fresh |
