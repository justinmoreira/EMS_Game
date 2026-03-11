const { findTrackedMessage, discord } = require('./helpers');

module.exports = async ({ github, context }) => {
  const pr = context.payload.pull_request;

  const tracked = await findTrackedMessage(github, context.repo, pr.number);
  if (!tracked) return;

  await discord('DELETE', `/messages/${tracked.msgId}`);

  await github.rest.issues.deleteComment({
    ...context.repo,
    comment_id: tracked.commentId,
  });
};
