const { mapUser, discord } = require('./helpers');

module.exports = async ({ github, context }) => {
  const pr = context.payload.pull_request;
  const author = mapUser(pr.user.login);
  const reviewers = pr.requested_reviewers.map((r) => mapUser(r.login));

  const content = reviewers.length
    ? `${author} requests review from ${reviewers.join(', ')}`
    : '';

  const msg = await discord('POST', '?wait=true', {
    content,
    embeds: [
      {
        title: pr.title,
        url: pr.html_url,
        description: `PR #${pr.number} by ${author}`,
        color: 5814783,
      },
    ],
  });

  await github.rest.issues.createComment({
    ...context.repo,
    issue_number: pr.number,
    body: `<!-- discord-msg-id:${msg.id} -->`,
  });
};
