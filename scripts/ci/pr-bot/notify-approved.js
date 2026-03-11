const { mapUser, findTrackedMessage, discord } = require('./helpers');

module.exports = async ({ github, context }) => {
  const pr = context.payload.pull_request;
  const reviewer = context.payload.review.user.login;
  const author = mapUser(pr.user.login);

  const tracked = await findTrackedMessage(github, context.repo, pr.number);
  if (!tracked) return;

  await discord('DELETE', `/messages/${tracked.msgId}`);

  const msg = await discord('POST', '?wait=true', {
    content: `${author} your PR was approved by ${reviewer}`,
    embeds: [
      {
        title: `READY TO MERGE: ${pr.title}`,
        url: pr.html_url,
        description: `PR #${pr.number} by ${author}`,
        color: 3066993,
      },
    ],
  });

  await github.rest.issues.updateComment({
    ...context.repo,
    comment_id: tracked.commentId,
    body: `<!-- discord-msg-id:${msg.id} -->`,
  });
};
