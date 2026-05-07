# Contributing to Carbon

Contributions are what make the open source community such an amazing place to learn, inspire, and create. Any contributions you make are **greatly appreciated**.

## House Rules (for PRs and Issues)

### 👥 Prevent Work Duplication

Before submitting a new issue or PR, check if it already exists in the [Issues](https://github.com/crbnos/carbon/issues) or [Pull Requests](https://github.com/crbnos/carbon/pulls).

### ✅ Work Only on Approved Issues

For feature requests, please wait for a core team member to approve and remove the `🚨 needs approval` label before you start coding or submitting a PR.

For bugs, security, performance, documentation, etc., you can start coding immediately—even if the `🚨 needs approval` label is present.

We highly value new feature ideas, but to maintain consistency in the product direction, they must go through a review and approval process.

### 🚫 Don’t Just Drop a Link

Avoid posting third-party links (e.g., Slack threads or Linear tickets) without context. A GitHub issue or PR should stand on its own—reviewers shouldn’t have to chase information across multiple tools to understand the context.

### 👀 Think Like a Reviewer

Put yourself in the reviewer’s shoes. What would you want to know if reading this for the first time? Are there key decisions, goals, or constraints that need clarification? Does the PR assume knowledge that isn’t obvious? Are there related issues or previous PRs that should be linked?

### 🧵 Bring in Context from Private Channels

If the task originated from a private conversation (e.g., Slack), take a moment to extract the relevant details and include them in the GitHub issue or PR. Avoid sharing sensitive information, but make sure important reasoning is captured.

> Example:  
> “A user requested feature X to solve problem Y. I considered approaches A, B, and C, but chose C for the following reasons…”

### 📚 Treat It Like Documentation

GitHub is a shared source of truth. Every issue and PR contributes to the long-term understanding of the codebase. Write clearly enough that someone—possibly you—can revisit it months later and still understand what happened and why.

### ✅ Summarize Your PR at the Top

Even if the code changes are minor or self-explanatory, a short written summary helps reviewers quickly understand the intent. You can use GitHub Copilot’s auto-summarize feature, but make sure to verify it for accuracy and relevance.

### 🔗 Use GitHub Keywords to Auto-Link Issues

Use phrases like “Closes #123” or “Fixes #456” in your PR descriptions. This automatically links your PR to the related issue and closes it once merged—keeping everything traceable and organized.

### 🧪 Mention What Was Tested (and How)

Explain how you validated your changes. It doesn’t need to be exhaustive—just enough to give reviewers confidence that things were tested and work as expected.

> Example:  
> “Tested locally with mock data and confirmed the flow works on staging.”

### 🧠 Assume Future-You Won’t Remember

Write with the future in mind. If there are trade-offs, edge cases, or temporary workarounds, document them clearly so they don’t get lost or misinterpreted later.

## Priorities

<table>
  <tr>
    <td><strong>Type of Issue</strong></td>
    <td><strong>Priority</strong></td>
  </tr>
  <tr>
    <td>Minor improvements, non-core feature requests</td>
    <td>
      <a href="https://github.com/crbnos/carbon/issues?q=is:issue+is:open+sort:updated-desc+label:%22Low+priority%22">
        <img src="https://img.shields.io/badge/-Low%20Priority-green">
      </a>
    </td>
  </tr>
  <tr>
    <td>Confusing UX (but still functional)</td>
    <td>
      <a href="https://github.com/crbnos/carbon/issues?q=is:issue+is:open+sort:updated-desc+label:%22Medium+priority%22">
        <img src="https://img.shields.io/badge/-Medium%20Priority-yellow">
      </a>
    </td>
  </tr>
  <tr>
    <td>Core Features (Booking page, availability, timezone calculation)</td>
    <td>
      <a href="https://github.com/crbnos/carbon/issues?q=is:issue+is:open+sort:updated-desc+label:%22High+priority%22">
        <img src="https://img.shields.io/badge/-High%20Priority-orange">
      </a>
    </td>
  </tr>
  <tr>
    <td>Core Bugs (Login, Booking page, Emails not working)</td>
    <td>
      <a href="https://github.com/crbnos/carbon/issues?q=is:issue+is:open+sort:updated-desc+label:Urgent">
        <img src="https://img.shields.io/badge/-Urgent-red">
      </a>
    </td>
  </tr>
</table>

## Developing

[See README](https://github.com/crbnos/carbon#development)

## Building

You can build the project with:

```bash
pnpm run build
```

Please ensure that you can make a full production build before pushing code.

## Testing

More info on how to add new tests coming soon.

#### Resolving Issues

## Linting

To check the formatting of your code:

```sh
pnpm run lint
```

If you get errors, be sure to fix them before committing.

## Making a Pull Request

- Be sure to [check the "Allow edits from maintainers" option](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/working-with-forks/allowing-changes-to-a-pull-request-branch-created-from-a-fork) when creating your PR. (This option isn't available if you're [contributing from a fork belonging to an organization](https://github.com/orgs/community/discussions/5634))
- If your PR refers to or fixes an issue, add `refs #XXX` or `fixes #XXX` to the PR description. Replace `XXX` with the respective issue number. See more about [linking a pull request to an issue](https://docs.github.com/en/issues/tracking-your-work-with-issues/linking-a-pull-request-to-an-issue).
- Fill out the PR template accordingly.
- Lastly, make sure to keep your branches updated (e.g., click the `Update branch` button on the GitHub PR page).
