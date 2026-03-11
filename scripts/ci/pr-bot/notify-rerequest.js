const { mapUser, findTrackedMessage, discord } = require('./helpers');

module.exports = async ({ github, context }) => {
  const pr = context.payload.pull_request;
  const reviewers = pr.requested_reviewers.map((r) => mapUser(r.login));

  const tracked = await findTrackedMessage(github, context.repo, pr.number);
  if (!tracked) return;

  // Delete the old message
  await discord('DELETE', `/messages/${tracked.msgId}`);

  const content = reviewers.length
    ? `${pr.user.login} requests re-review from ${reviewers.join(', ')}`
    : `${pr.user.login} opened a PR`;

  // Post a new message so it appears at the bottom of the channel
  const msg = await discord('POST', '?wait=true', {
    content,
    embeds: [
      {
        title: pr.title,
        url: pr.html_url,
        description: `PR #${pr.number} by ${mapUser(pr.user.login)}`,
        color: 5814783,
      },
    ],
  });

  // Update the tracked comment with the new message ID
  await github.rest.issues.updateComment({
    ...context.repo,
    comment_id: tracked.commentId,
    body: `<!-- discord-msg-id:${msg.id} -->`,
  });
};
