const { mapUser, findTrackedMessage, discord } = require('./helpers');

module.exports = async ({ github, context }) => {
  const pr = context.payload.pull_request;
  const reviewers = pr.requested_reviewers.map((r) => mapUser(r.login));

  const tracked = await findTrackedMessage(github, context.repo, pr.number);
  if (!tracked) return;

  const content = reviewers.length
    ? `${pr.user.login} requests review from ${reviewers.join(', ')}`
    : `${pr.user.login} opened a PR`;

  await discord('PATCH', `/messages/${tracked.msgId}`, {
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
};
